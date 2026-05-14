import 'dart:async';
import 'dart:convert';
import 'package:estacionamientotarifado/core/colores.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:estacionamientotarifado/consultas/consultar_multas.dart';
import 'package:estacionamientotarifado/consultas/credencial.dart';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart'
    as svc2;
import 'package:estacionamientotarifado/servicios/servicioNotificacionesBackground.dart';
import 'package:estacionamientotarifado/servicios/servicioWebSocket.dart';
import 'package:estacionamientotarifado/servicios/monitorDatos.dart';
import 'package:estacionamientotarifado/consultas/monitor_datos_screen.dart';
import 'package:estacionamientotarifado/tarjetas/views/EstacionamientoScreen.dart';
import 'package:estacionamientotarifado/tarjetas/views/NotificacionScreen.dart';
import 'package:estacionamientotarifado/tarjetas/views/Notificacionusuario.dart';
import 'package:estacionamientotarifado/admin/estaciones_screen.dart';
import 'package:estacionamientotarifado/consultas/admin_usuarios_screen.dart';
import 'package:estacionamientotarifado/consultas/cambiar_contrasena.dart';
import 'package:estacionamientotarifado/consultas/personas_registradas_screen.dart';
import 'package:estacionamientotarifado/consultas/vehicle_screen.dart';
import 'package:estacionamientotarifado/consultas/manual_usuario_screen.dart';
import 'package:estacionamientotarifado/login_screan.dart';
import 'package:estacionamientotarifado/servicios/servicioPermisos.dart';
import 'package:estacionamientotarifado/shared/widgets/fondo_decorado_app.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String username = '';
  String name = '';
  String email = '';
  String lastLogin = '';
  String _versionProyecto = '';
  int usuarioId = 0;
  bool _isSuperuser = false;
  Map<String, bool> _permisos = PermissionsService.defaultPermisos();

  // Métricas del mes
  int _totalMultasMes = 0;
  int _multasHoy = 0;
  // Métricas tarjetas
  int _tarjetasMes = 0;
  int _tarjetasHoy = 0;
  int _placasUnicasMes = 0;
  bool _metricasCargadas = false;

  /// Ranking de usuarios del mes: [(nombre, cantidad)]
  List<Map<String, dynamic>> _rankingUsuarios = [];

  /// Timer para guardar ranking en caché cada cierto tiempo
  Timer? _rankingSaveTimer;

  StreamSubscription? _wsMultasSub;
  StreamSubscription? _wsTarjetasSub;
  late AppLifecycleListener _lifecycleListener;

  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    // Escuchar cambios en el ciclo de vida de la app
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        debugPrint('🔄 App reanudada - sincronizando caché');
        try {
          unawaited(ServicioNotificacionesBackground.actualizarAhora());
        } catch (e) {
          debugPrint('⚠️ Error en actualizarAhora: $e');
        }
      },
    );

    _cargarVersionProyecto();
    _loadUserData();

    // Recuperar ranking anterior (si existe) para mostrar inmediatamente
    _recuperarRankingEnCache();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
  }

  Future<void> _cargarVersionProyecto() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionProyecto = 'v${packageInfo.version}+${packageInfo.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionProyecto = 'v1.0.0+10';
      });
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getInt('id') ?? 0;
    final superuser = prefs.getBool('is_superuser') == true;
    debugPrint('[Home] is_superuser leído de prefs: $superuser');
    final permisos = await PermissionsService.getPermisos(uid);
    setState(() {
      username = prefs.getString('username') ?? '';
      name = prefs.getString('name') ?? '';
      email = prefs.getString('email') ?? '';
      usuarioId = uid;
      lastLogin = _formatDate(prefs.getString('last_login') ?? '');
      _isSuperuser = superuser;
      _permisos = permisos;
    });
    // Inicializar monitor de datos
    MonitorDatos.instancia.inicializar();
    final token = prefs.getString('token') ?? '';
    final cookie = prefs.getString('session_cookie') ?? '';
    // Iniciar WebSocket y suscribir canales para métricas en vivo
    ServicioWebSocket.instancia.conectar(token: token);
    _suscribirWsHome();
    // Cargar métricas: caché instantáneo → HTTP como fallback solo si caché vacía
    _cargarMetricas(prefs, token);
    // Pre-calentar cachés de otras pantallas en segundo plano
    // (cada preWarmCache verifica si ya hay caché y no hace HTTP si existe)
    unawaited(
      Future.wait([
        EstacionesAdminScreen.preWarmCache(token: token, sessionCookie: cookie),
        Notificacionesscreen.preWarmCache(),
        NotificacionesUsuarioScreen.preWarmCache(uid),
        AdminUsuariosScreen.preWarmCache(token: token, sessionCookie: cookie),
      ]).catchError((_) => <void>[]),
    );
  }

  bool _permitido(String key) {
    if (_isSuperuser) return true;
    return _permisos[key] ?? true;
  }

  /// Carga métricas con patrón cache-first → HTTP siempre como actualización.
  /// La caché se muestra al instante, luego HTTP refresca los datos en segundo plano.
  Future<void> _cargarMetricas(SharedPreferences prefs, String token) async {
    final now = DateTime.now();

    Uri uriTk(String path) {
      final base = 'https://simert.transitoelguabo.gob.ec$path';
      return token.isNotEmpty
          ? Uri.parse(base).replace(queryParameters: {'_tk': token})
          : Uri.parse(base);
    }

    try {
      // ═══ FASE 1: Caché → métricas visibles al instante ═══════════════
      var multas = await svc2.CacheDetallesService.leerMes();
      if (multas.isEmpty) {
        final raw = prefs.getString('multas');
        if (raw != null) {
          try {
            multas = (json.decode(raw) as List)
                .whereType<Map<String, dynamic>>()
                .toList();
          } catch (_) {}
        }
      }

      List<Map<String, dynamic>> tarjetas = [];
      final cTarjetas = prefs.getString('estacionamientos_tarjeta');
      if (cTarjetas != null) {
        try {
          tarjetas = (json.decode(cTarjetas) as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        } catch (_) {}
      }

      // Mostrar métricas de caché de inmediato
      _aplicarMultas(multas, now);
      _aplicarTarjetas(tarjetas, now);

      // ═══ FASE 2: HTTP siempre (refresca datos aunque haya caché) ═════
      if (token.isNotEmpty) {
        final resultados =
            await Future.wait([
              _fetchMultasHttp(uriTk, prefs),
              _fetchTarjetasHttp(uriTk, prefs),
            ]).timeout(
              const Duration(seconds: 15),
              onTimeout: () => [multas, tarjetas],
            );

        final multasHttp = resultados[0];
        final tarjetasHttp = resultados[1];

        // Solo actualizar si HTTP devolvió datos (si falló, mantener caché)
        if (multasHttp.isNotEmpty) {
          _aplicarMultas(multasHttp, now);
        }
        if (tarjetasHttp.isNotEmpty) {
          _aplicarTarjetas(tarjetasHttp, now);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _metricasCargadas = true);
    }
  }

  // ── Aplicar métricas por sección ─────────────────────────────────────────

  void _aplicarMultas(List<Map<String, dynamic>> multas, DateTime now) {
    final multasMes = multas.where((m) {
      try {
        final dt = DateTime.parse(m['fechaEmision'] as String);
        return dt.year == now.year && dt.month == now.month;
      } catch (_) {
        return false;
      }
    }).toList();
    final hoy = multasMes.where((m) {
      try {
        final dt = DateTime.parse(m['fechaEmision'] as String);
        return dt.day == now.day;
      } catch (_) {
        return false;
      }
    }).length;

    if (mounted) {
      setState(() {
        _totalMultasMes = multasMes.length;
        _multasHoy = hoy;
        _metricasCargadas = true;
      });
    }
  }

  void _aplicarTarjetas(List<Map<String, dynamic>> tarjetas, DateTime now) {
    final tarjetasUsuario = _isSuperuser
        ? tarjetas
        : tarjetas.where((t) => (t['usuario'] as int?) == usuarioId).toList();

    final tarjetasMes = tarjetasUsuario.where((t) {
      try {
        final dt = DateTime.parse(t['fecha'] as String);
        return dt.year == now.year && dt.month == now.month;
      } catch (_) {
        return false;
      }
    }).toList();
    final hoy = tarjetasMes.where((t) {
      try {
        final dt = DateTime.parse(t['fecha'] as String);
        return dt.day == now.day;
      } catch (_) {
        return false;
      }
    }).length;
    final placas = tarjetasMes
        .map((t) => t['placa'] as String? ?? '')
        .toSet()
        .where((p) => p.isNotEmpty)
        .length;

    if (mounted) {
      setState(() {
        _tarjetasMes = tarjetasMes.length;
        _tarjetasHoy = hoy;
        _placasUnicasMes = placas;
        _metricasCargadas = true;
      });
    }

    // Calcular ranking asincronicamente
    unawaited(_recalcularRankingHoy(tarjetas, now));
  }

  // ── Fetch HTTP (fallback cuando caché vacía) ─────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchMultasHttp(
    Uri Function(String) uriTk,
    SharedPreferences prefs,
  ) async {
    try {
      final resp = await HttpMonitorizado.get(uriTk('/api/details_multas'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        List<Map<String, dynamic>> multas;
        if (data is List) {
          multas = data.whereType<Map<String, dynamic>>().toList();
        } else if (data is Map && data['results'] is List) {
          multas = (data['results'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        } else {
          return [];
        }
        if (multas.isNotEmpty) {
          await prefs.setString('multas', json.encode(multas));
        }
        return multas;
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchTarjetasHttp(
    Uri Function(String) uriTk,
    SharedPreferences prefs,
  ) async {
    try {
      final resp = await HttpMonitorizado.get(uriTk('/api/est_tarjeta/'));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        List<Map<String, dynamic>> tarjetas;
        if (data is List) {
          tarjetas = data.whereType<Map<String, dynamic>>().toList();
        } else if (data is Map && data['results'] is List) {
          tarjetas = (data['results'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        } else {
          return [];
        }
        if (tarjetas.isNotEmpty) {
          await prefs.setString(
            'estacionamientos_tarjeta',
            json.encode(tarjetas),
          );
        }
        return tarjetas;
      }
    } catch (_) {}
    return [];
  }

  // ── WebSocket: suscripción a canales para métricas en vivo ───────────────

  void _suscribirWsHome() {
    final ws = ServicioWebSocket.instancia;
    ws.suscribir('multas');
    ws.suscribir('tarjetas');

    _wsMultasSub?.cancel();
    _wsMultasSub = ws.escuchar('multas').listen((evento) {
      if (!mounted) return;
      final now = DateTime.now();
      if (evento.accion == 'snapshot' && evento.datos is List) {
        final multas = (evento.datos as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        SharedPreferences.getInstance().then(
          (p) => p.setString('multas', json.encode(multas)),
        );
        _aplicarMultas(multas, now);
      } else if (evento.accion == 'create' && evento.datos is Map) {
        _onNuevaMultaWs(evento.datos as Map<String, dynamic>);
      }
    });

    _wsTarjetasSub?.cancel();
    _wsTarjetasSub = ws.escuchar('tarjetas').listen((evento) {
      if (!mounted) return;
      final now = DateTime.now();
      if (evento.accion == 'snapshot' && evento.datos is List) {
        final tarjetasWs = (evento.datos as List)
            .whereType<Map<String, dynamic>>()
            .toList();

        // Hacer MERGE con los datos existentes en caché: el snapshot del WS
        // solo trae registros activos (estacionId > 0), pero necesitamos
        // mantener los registros históricos del mes para las métricas.
        SharedPreferences.getInstance().then((p) async {
          final existentes = p.getString('estacionamientos_tarjeta');
          List<Map<String, dynamic>> merge = [];
          if (existentes != null) {
            try {
              merge = (json.decode(existentes) as List)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            } catch (_) {}
          }
          // Agregar/actualizar registros del WS
          for (final t in tarjetasWs) {
            final estacionId = t['estacion'] as int?;
            if (estacionId != null && estacionId > 0) {
              final idx = merge.indexWhere(
                (e) => (e['estacion'] as int?) == estacionId,
              );
              if (idx == -1) {
                merge.add(t);
              } else {
                merge[idx] = t;
              }
            }
          }
          // Guardar merge en caché
          await p.setString('estacionamientos_tarjeta', json.encode(merge));
        });

        // Aplicar métricas con los datos del WS (activos) + merge con existentes
        _aplicarTarjetas(tarjetasWs, now);
        // Recalcular ranking cuando llega snapshot
        unawaited(_recalcularRankingHoy(tarjetasWs, now));
      } else if (evento.accion == 'create' && evento.datos is Map) {
        _onNuevaTarjetaWs(evento.datos as Map<String, dynamic>);
      }
    });
  }

  void _onNuevaMultaWs(Map<String, dynamic> m) {
    try {
      final dt = DateTime.parse(m['fechaEmision'] as String);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && mounted) {
        setState(() {
          _totalMultasMes++;
          if (dt.day == now.day) _multasHoy++;
        });
      }
    } catch (_) {}
  }

  void _onNuevaTarjetaWs(Map<String, dynamic> t) {
    try {
      final dt = DateTime.parse(t['fecha'] as String);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && mounted) {
        final userId = t['usuario'] as int?;
        final esDelUsuarioActual = userId == usuarioId;
        final debeActualizar = _isSuperuser || esDelUsuarioActual;

        if (debeActualizar) {
          setState(() {
            _tarjetasMes++;
            if (dt.day == now.day) _tarjetasHoy++;
          });

          // Si es de hoy, actualizar ranking
          if (dt.day == now.day &&
              userId != null &&
              _rankingUsuarios.isNotEmpty) {
            final idx = _rankingUsuarios.indexWhere(
              (r) => r['usuario_id'] == userId,
            );
            if (idx >= 0) {
              _rankingUsuarios[idx]['total'] =
                  (_rankingUsuarios[idx]['total'] as int) + 1;
              // Re-ordenar ranking
              _rankingUsuarios.sort(
                (a, b) => (b['total'] as int).compareTo(a['total'] as int),
              );
              setState(() {});
            } else {
              // Si el usuario no está en el ranking, agrégalo
              _rankingUsuarios.add({
                'usuario_id': userId,
                'nombre': t['usuario_nombre'] as String? ?? 'Usuario #$userId',
                'total': 1,
              });
              _rankingUsuarios.sort(
                (a, b) => (b['total'] as int).compareTo(a['total'] as int),
              );
              setState(() {});
            }
          }
        }
      }
    } catch (_) {}
  }

  String _formatDate(String isoDate) {
    try {
      final dateTime = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    } catch (_) {
      return "Sin registro";
    }
  }

  Future<void> _logout() async {
    // Desconectar WebSocket antes de limpiar datos
    ServicioWebSocket.instancia.desconectar();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Recalcula el ranking de usuarios para HOY
  /// Obtiene nombres de múltiples fuentes: cache, tarjetas previas, o genéricos
  Future<void> _recalcularRankingHoy(
    List<Map<String, dynamic>> tarjetas,
    DateTime now,
  ) async {
    try {
      // Agrupar tarjetas de HOY por usuario
      final Map<int, int> conteoUsuarios = {};
      for (final t in tarjetas) {
        try {
          final dt = DateTime.parse(t['fecha'] as String);
          if (dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day) {
            final userId = (t['usuario'] as int?) ?? 0;
            if (userId > 0) {
              conteoUsuarios[userId] = (conteoUsuarios[userId] ?? 0) + 1;
            }
          }
        } catch (_) {}
      }

      if (conteoUsuarios.isEmpty) {
        if (mounted) setState(() => _rankingUsuarios = []);
        return;
      }

      // Obtener nombres desde múltiples fuentes
      final prefs = await SharedPreferences.getInstance();
      final Map<int, String> nombres = {};

      // 1️⃣ Intentar desde cache_admin_usuarios
      final usuariosJson = prefs.getString('cache_admin_usuarios');
      if (usuariosJson != null) {
        try {
          final lista = json.decode(usuariosJson) as List;
          for (final u in lista) {
            if (u is Map<String, dynamic> && u['id'] != null) {
              final id = u['id'] as int;
              final nm =
                  u['name'] as String? ?? u['username'] as String? ?? 'Usuario';
              nombres[id] = nm;
            }
          }
        } catch (_) {}
      }

      // 2️⃣ Agregar nombres desde tarjetas si existen
      for (final t in tarjetas) {
        try {
          final userId = (t['usuario'] as int?) ?? 0;
          if (userId > 0 && !nombres.containsKey(userId)) {
            final nm = t['usuario_nombre'] as String? ?? 'Usuario #$userId';
            nombres[userId] = nm;
          }
        } catch (_) {}
      }

      // 3️⃣ Agregar nombre del usuario actual
      nombres[usuarioId] = name.isNotEmpty ? name : username;

      // Construir ranking
      final rankingCalc =
          conteoUsuarios.entries
              .map(
                (e) => {
                  'usuario_id': e.key,
                  'nombre': nombres[e.key] ?? 'Usuario #${e.key}',
                  'total': e.value,
                },
              )
              .toList()
            ..sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

      if (mounted) {
        setState(() => _rankingUsuarios = rankingCalc);
        // Guardar en caché para recuperar si hay errores después
        unawaited(_guardarRankingEnCache());
      }
    } catch (e) {
      debugPrint('❌ Error recalculando ranking: $e');
      // Si falla, recuperar del caché
      unawaited(_recuperarRankingEnCache());
    }
  }

  /// Recupera el ranking guardado en caché para mostrarlo inmediatamente
  Future<void> _recuperarRankingEnCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rankingJson = prefs.getString('ranking_usuarios_hoy');
      if (rankingJson != null) {
        try {
          final ranking = (json.decode(rankingJson) as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          if (ranking.isNotEmpty && mounted) {
            setState(() => _rankingUsuarios = ranking);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Guarda el ranking en caché para recuperarlo luego
  Future<void> _guardarRankingEnCache() async {
    try {
      if (_rankingUsuarios.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ranking_usuarios_hoy',
        json.encode(_rankingUsuarios),
      );
    } catch (e) {
      debugPrint('⚠️ Error guardando ranking en caché: $e');
    }
  }

  @override
  void dispose() {
    _wsMultasSub?.cancel();
    _wsTarjetasSub?.cancel();
    _rankingSaveTimer?.cancel();
    _lifecycleListener.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _mostrarInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: AppColores.gradientePrincipal,
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Información',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Panel Principal SIMERT',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Muestra las métricas del mes, accesos rápidos a las funciones principales y notificaciones del sistema.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendido'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        title: const Text(
          'Bienvenido',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColores.gradientePrincipal,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Información',
            onPressed: () => _mostrarInfo(context),
          ),
        ],
      ),
      drawer: _buildDrawer(context, scale),
      body: FondoDecoradoApp(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24 * scale,
                vertical: 20 * scale,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    children: [
                      SizedBox(height: 12 * scale),
                      _buildHeroPanel(scale),
                      SizedBox(height: 20 * scale),
                      _buildMetricas(scale),
                      SizedBox(height: 16 * scale),
                      Text(
                        'Usa el menú lateral para navegar por los módulos disponibles.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13 * scale,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      SizedBox(height: 10 * scale),
                      Text(
                        _versionProyecto.isEmpty
                            ? 'Cargando version...'
                            : _versionProyecto,
                        style: TextStyle(
                          color: Colors.white30,
                          fontSize: 11 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPanel(double scale) {
    final saludo = name.isNotEmpty ? name : 'Usuario';
    final anchoMaximo = 680 * scale;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: anchoMaximo),
      padding: EdgeInsets.all(20 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 34 * scale,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 24 * scale,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 16 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12 * scale,
                        vertical: 7 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _isSuperuser
                            ? 'Perfil administrador'
                            : 'Perfil operativo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: 12 * scale),
                    Text(
                      'Hola, $saludo',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Text(
                      'Panel central con tus datos de cuenta y el estado actual de tu actividad.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 14 * scale,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18 * scale),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 10 * scale;
              final esMovil = constraints.maxWidth < 620;
              final anchoTarjeta = esMovil
                  ? constraints.maxWidth
                  : ((constraints.maxWidth - spacing) / 2).clamp(220.0, 360.0);

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _heroDato(
                    icon: Icons.alternate_email_rounded,
                    etiqueta: 'Usuario',
                    valor: username.isEmpty ? 'No disponible' : '@$username',
                    scale: scale,
                    ancho: anchoTarjeta,
                  ),
                  _heroDato(
                    icon: Icons.email_outlined,
                    etiqueta: 'Correo',
                    valor: email.isEmpty ? 'No disponible' : email,
                    scale: scale,
                    ancho: anchoTarjeta,
                  ),
                  _heroDato(
                    icon: Icons.history_toggle_off_rounded,
                    etiqueta: 'Último acceso',
                    valor: lastLogin,
                    scale: scale,
                    ancho: anchoTarjeta,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _heroDato({
    required IconData icon,
    required String etiqueta,
    required String valor,
    required double scale,
    required double ancho,
  }) {
    return Container(
      width: ancho,
      constraints: BoxConstraints(minHeight: 72 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18 * scale),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  valor,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Métricas del mes ─────────────────────────────────────────────────────
  Widget _buildMetricas(double scale) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final mes = meses[DateTime.now().month - 1];

    return Column(
      children: [
        // Encabezado
        Row(
          children: [
            const Icon(
              Icons.bar_chart_rounded,
              color: Colors.white70,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              'Mis métricas — $mes',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (!_metricasCargadas)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white54,
                ),
              ),
          ],
        ),
        SizedBox(height: 10 * scale),

        // Grupo Multas
        _buildGrupoMetrica(
          scale: scale,
          titulo: 'Infracciones',
          icono: Icons.gavel_rounded,
          chips: [
            _metricaChip(
              icon: Icons.receipt_long_rounded,
              label: 'Este mes',
              value: '$_totalMultasMes',
              scale: scale,
            ),
            _metricaChip(
              icon: Icons.today_rounded,
              label: 'Hoy',
              value: '$_multasHoy',
              scale: scale,
            ),
          ],
        ),
        SizedBox(height: 10 * scale),

        // Grupo Tarjetas
        _buildGrupoMetrica(
          scale: scale,
          titulo: 'Control de Tarjetas',
          icono: Icons.credit_card_rounded,
          chips: [
            _metricaChip(
              icon: Icons.local_parking_rounded,
              label: 'Este mes',
              value: '$_tarjetasMes',
              scale: scale,
            ),
            _metricaChip(
              icon: Icons.today_rounded,
              label: 'Hoy',
              value: '$_tarjetasHoy',
              scale: scale,
            ),
            _metricaChip(
              icon: Icons.directions_car_rounded,
              label: 'Placas\n\u00fanicas',
              value: '$_placasUnicasMes',
              scale: scale,
            ),
          ],
        ),

        // Ranking de usuarios del día (siempre visible)
        SizedBox(height: 10 * scale),
        _buildRankingUsuarios(scale),
      ],
    );
  }

  Widget _buildGrupoMetrica({
    required double scale,
    required String titulo,
    required IconData icono,
    required List<Widget> chips,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: Colors.white60, size: 13 * scale),
              const SizedBox(width: 5),
              Text(
                titulo,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          Row(
            children:
                chips
                    .map((c) => Expanded(child: c))
                    .expand((w) => [w, SizedBox(width: 8 * scale)])
                    .toList()
                  ..removeLast(),
          ),
        ],
      ),
    );
  }

  Widget _metricaChip({
    required IconData icon,
    required String label,
    required String value,
    required double scale,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 12 * scale,
        horizontal: 8 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20 * scale),
          SizedBox(height: 6 * scale),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 3 * scale),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 10 * scale,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Ranking de usuarios del día (top por estacionamientos registrados hoy)
  /// Visible para todos los usuarios, se actualiza en tiempo real
  Widget _buildRankingUsuarios(double scale) {
    final maxTotal = _rankingUsuarios.isNotEmpty
        ? (_rankingUsuarios.first['total'] as int)
        : 1;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(
            children: [
              const Icon(
                Icons.leaderboard_rounded,
                color: Colors.amberAccent,
                size: 15,
              ),
              const SizedBox(width: 6),
              const Text(
                'Ranking — Hoy',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.emoji_events_rounded,
                color: Colors.amber.shade300,
                size: 14,
              ),
            ],
          ),
          SizedBox(height: 2 * scale),
          // Subtítulo: quién registra más estacionamientos
          Text(
            'Usuarios que registran ocupación de estacionamientos',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10 * scale,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 10 * scale),

          // Si no hay datos, mostrar mensaje informativo
          if (_rankingUsuarios.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * scale),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14 * scale,
                    color: Colors.white38,
                  ),
                  SizedBox(width: 6 * scale),
                  Text(
                    'Aún no hay registros de ocupación hoy',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12 * scale,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            )
          else
            // Lista de usuarios ordenados
            ...List.generate(_rankingUsuarios.length.clamp(0, 10), (i) {
              final item = _rankingUsuarios[i];
              final nombre = item['nombre'] as String;
              final total = item['total'] as int;
              final pct = maxTotal > 0 ? total / maxTotal : 0.0;

              Color medalla;
              if (i == 0) {
                medalla = Colors.amber;
              } else if (i == 1) {
                medalla = Colors.grey.shade400;
              } else if (i == 2) {
                medalla = Colors.brown.shade300;
              } else {
                medalla = Colors.white38;
              }

              return Padding(
                padding: EdgeInsets.only(bottom: 6 * scale),
                child: Row(
                  children: [
                    // Posición
                    Container(
                      width: 22 * scale,
                      alignment: Alignment.center,
                      child: i < 3
                          ? Icon(
                              Icons.emoji_events_rounded,
                              color: medalla,
                              size: 16 * scale,
                            )
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11 * scale,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    SizedBox(width: 8 * scale),

                    // Nombre
                    SizedBox(
                      width: 100 * scale,
                      child: Text(
                        nombre,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 6 * scale),

                    // Barra de progreso
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8 * scale,
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            i == 0
                                ? Colors.amber
                                : i == 1
                                ? Colors.grey.shade400
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8 * scale),

                    // Total
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * scale,
                        vertical: 3 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$total',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // Drawer lateral
  Drawer _buildDrawer(BuildContext context, double scale) {
    return Drawer(
      backgroundColor: AppColores.acentoFondo,
      child: Column(
        children: [
          // ── Header con gradiente ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 48 * scale, 20, 24),
            decoration: const BoxDecoration(
              gradient: AppColores.gradientePrincipal,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32 * scale,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 28 * scale,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 12 * scale),
                Text(
                  name.isNotEmpty ? name : 'Usuario',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4 * scale),
                Row(
                  children: [
                    const Icon(
                      Icons.alternate_email,
                      color: Colors.white60,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        username,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12 * scale,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Ítems de navegación ───────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              children: [
                if (_permitido(PermisoKey.vehiculos))
                  _menuTile(
                    Icons.directions_car_rounded,
                    'Datos de Vehículos',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VehicleScreen()),
                    ),
                    scale: scale,
                  ),
                if (_permitido(PermisoKey.tarjetas))
                  _menuTile(
                    Icons.credit_card_rounded,
                    'Control de Tarjetas',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EstacionamientoScreen(),
                      ),
                    ),
                    scale: scale,
                  ),
                if (_permitido(PermisoKey.multas))
                  _menuTile(
                    Icons.search_rounded,
                    'Consultar Multas',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ConsultaNotificacionesScreen(),
                      ),
                    ),
                    scale: scale,
                  ),
                if (_permitido(PermisoKey.notificaciones))
                  _menuTile(
                    Icons.receipt_long_rounded,
                    'Notificaciones',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const Notificacionesscreen(),
                      ),
                    ),
                    scale: scale,
                  ),
                if (_permitido(PermisoKey.misNotificaciones))
                  _menuTile(
                    Icons.notifications_active_rounded,
                    'Mis Notificaciones',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificacionesUsuarioScreen(),
                      ),
                    ),
                    scale: scale,
                  ),
                if (_permitido(PermisoKey.beneficiarios))
                  _menuTile(
                    Icons.people_alt_rounded,
                    'Beneficio Adult. Mayor / Discap.',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonasRegistradasScreen(
                          canWrite:
                              _isSuperuser ||
                              (_permisos[PermisoKey.beneficiariosEscritura] ??
                                  false),
                        ),
                      ),
                    ),
                    scale: scale,
                  ),
                if (_permitido(PermisoKey.credencial))
                  _menuTile(
                    Icons.badge_rounded,
                    'Credencial',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DynamicCredentialScreen(),
                      ),
                    ),
                    scale: scale,
                  ),
                _menuTile(
                  Icons.data_usage_rounded,
                  'Consumo de Datos',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MonitorDatosScreen(),
                    ),
                  ),
                  scale: scale,
                ),
                _menuTile(
                  Icons.lock_reset_rounded,
                  'Cambiar contraseña',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CambiarContrasenaScreen(),
                    ),
                  ),
                  scale: scale,
                ),
                _menuTile(
                  Icons.menu_book_rounded,
                  'Manual de Usuario',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManualUsuarioScreen(),
                    ),
                  ),
                  scale: scale,
                ),
                // ── Sección Administración (solo superusuario) ─────────
                if (_isSuperuser) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 12,
                          color: AppColores.acentoAdmin,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ADMINISTRACIÓN',
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                            color: AppColores.acentoAdmin,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _menuTile(
                    Icons.manage_accounts_rounded,
                    'Gestión de Accesos',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminUsuariosScreen(),
                      ),
                    ),
                    scale: scale,
                    isAdmin: true,
                  ),
                  _menuTile(
                    Icons.local_parking_rounded,
                    'Gestión de Estaciones',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EstacionesAdminScreen(),
                      ),
                    ),
                    scale: scale,
                    isAdmin: true,
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(color: Color(0xFFE0E0E0), height: 1),
                const SizedBox(height: 8),
                _menuTile(
                  Icons.logout_rounded,
                  'Cerrar sesión',
                  _logout,
                  scale: scale,
                  isLogout: true,
                ),
              ],
            ),
          ),

          // ── Versión ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _versionProyecto.isEmpty
                  ? 'Cargando version...'
                  : _versionProyecto,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 11 * scale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    required double scale,
    bool isLogout = false,
    bool isAdmin = false,
  }) {
    final iconColor = isLogout
        ? Colors.red.shade600
        : isAdmin
        ? AppColores.acentoAdmin
        : AppColores.acentoAdmin;
    final iconBg = isLogout
        ? Colors.red.shade50
        : isAdmin
        ? AppColores.acentoAdmin.withValues(alpha: 0.15)
        : AppColores.acentoAdmin.withValues(alpha: 0.10);
    final textColor = isLogout
        ? Colors.red.shade600
        : isAdmin
        ? AppColores.acentoAdmin
        : AppColores.primario;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14 * scale,
              vertical: 12 * scale,
            ),
            child: Row(
              children: [
                Container(
                  width: 36 * scale,
                  height: 36 * scale,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18 * scale),
                ),
                SizedBox(width: 14 * scale),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isLogout)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                    size: 18 * scale,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

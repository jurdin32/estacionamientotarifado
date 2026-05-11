import 'dart:async';
import 'dart:convert';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart';
import 'package:estacionamientotarifado/servicios/servicioTiposMultas.dart';
import 'package:estacionamientotarifado/servicios/servicioWebSocket.dart';
import 'package:estacionamientotarifado/shared/widgets/campo_busqueda_app.dart';
import 'package:estacionamientotarifado/tarjetas/models/Notificaciones2.dart';
import 'package:estacionamientotarifado/tarjetas/models/Multa.dart';
import 'package:estacionamientotarifado/core/colores.dart';
import 'package:estacionamientotarifado/shared/widgets/estado_carga_app.dart';
import 'package:estacionamientotarifado/shared/widgets/tarjeta_lista_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificacionesUsuarioScreen extends StatefulWidget {
  final bool mostrarSoloMesActual;

  const NotificacionesUsuarioScreen({
    super.key,
    this.mostrarSoloMesActual = true,
  });

  /// Llama esto desde HomeScreen para pre-cargar las notificaciones del mes en caché.
  static Future<void> preWarmCache(int userId) async {
    final existing = await NotifMesCache.leer(userId);
    if (existing != null && existing.isNotEmpty) return; // ya hay caché
    try {
      final svc = NotificacionService();
      final todas = await svc.getNotificaciones();
      final delMes = svc.filtrarNotificacionesMesActual(todas);
      if (delMes.isNotEmpty) await NotifMesCache.guardar(userId, delMes);
    } catch (_) {
      // Silencioso — se cargará al entrar a la pantalla
    }
  }

  @override
  State<NotificacionesUsuarioScreen> createState() =>
      _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesUsuarioScreen>
    with SingleTickerProviderStateMixin {
  // ─── Design tokens ────────────────────────────────────────────────────────
  static const Color _colorPrimario = AppColores.primario;
  static const Color _colorSecundario = AppColores.primarioDark;
  static const Color _colorTexto = AppColores.textoPrimario;

  // ─── State ────────────────────────────────────────────────────────────────
  final NotificacionService _svc = NotificacionService();
  late TabController _tabController;

  List<Notificacion> _notificaciones = [];
  Map<String, List<Notificacion>> _grupos = {
    'pagadas': [],
    'impagas': [],
    'impugnadas': [],
  };

  bool _cargando = true;
  String? _error;
  bool _mostrarSoloMesActual = true;
  bool _esSuperuser = false;
  int _userId = 0;
  String _filtroUsuario = 'todos';
  String _filtroPlaca = '';
  DateTime? _fechaInicioFiltro;
  DateTime? _fechaFinFiltro;
  String _operador = '';
  List<Notificacion> _todasNotificaciones = [];
  List<Multa> _catalogoMultas = [];
  final Map<int, String> _etiquetasUsuario = {};
  final TextEditingController _busquedaPlacaCtrl = TextEditingController();
  StreamSubscription? _wsNotifSub;

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mostrarSoloMesActual = widget.mostrarSoloMesActual;
    _cargar();
    _suscribirWsNotificaciones();
  }

  @override
  void dispose() {
    _wsNotifSub?.cancel();
    _busquedaPlacaCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ─── Data ─────────────────────────────────────────────────────────────────

  List<Notificacion> _ordenarLista(List<Notificacion> lista) {
    final copia = List<Notificacion>.from(lista);
    copia.sort((a, b) {
      try {
        return DateTime.parse(
          b.fechaEmision,
        ).compareTo(DateTime.parse(a.fechaEmision));
      } catch (_) {
        return 0;
      }
    });
    return copia;
  }

  DateTime? _fechaDeNotificacion(Notificacion n) {
    try {
      return DateTime.parse(n.fechaEmision).toLocal();
    } catch (_) {
      return null;
    }
  }

  bool _coincideConRango(DateTime? fecha) {
    if (fecha == null) return false;
    if (_fechaInicioFiltro == null || _fechaFinFiltro == null) return true;

    final ini = DateTime(
      _fechaInicioFiltro!.year,
      _fechaInicioFiltro!.month,
      _fechaInicioFiltro!.day,
    );
    final fin = DateTime(
      _fechaFinFiltro!.year,
      _fechaFinFiltro!.month,
      _fechaFinFiltro!.day,
      23,
      59,
      59,
    );
    return !fecha.isBefore(ini) && !fecha.isAfter(fin);
  }

  List<int> get _usuariosDisponibles {
    final ids = _todasNotificaciones.map((e) => e.usuario).toSet().toList();
    ids.sort();
    return ids;
  }

  String _nombreUsuario(int id) {
    final nombre = _etiquetasUsuario[id]?.trim() ?? '';
    if (nombre.isEmpty) return 'Usuario';
    return nombre;
  }

  String _nombreUsuarioTarjeta(int id) {
    final nombre = _etiquetasUsuario[id]?.trim() ?? '';
    if (nombre.isEmpty) return 'Usuario';
    return nombre;
  }

  Future<void> _cargarEtiquetasUsuarios() async {
    final prefs = await SharedPreferences.getInstance();
    final mapa = <int, String>{};

    final rawCache = prefs.getString('cache_admin_usuarios');
    if (rawCache != null && rawCache.isNotEmpty) {
      try {
        final decoded = json.decode(rawCache);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map<String, dynamic>) continue;
            final id = item['id'] as int? ?? 0;
            if (id <= 0) continue;
            final username = (item['username'] as String? ?? '').trim();
            final first = (item['first_name'] as String? ?? '').trim();
            final last = (item['last_name'] as String? ?? '').trim();
            final full = '$first $last'.trim();
            mapa[id] = full.isNotEmpty ? full : username;
          }
        }
      } catch (_) {}
    }

    if (mapa.isEmpty) {
      try {
        final token = (prefs.getString('token') ?? '').trim();
        final uri = token.isNotEmpty
            ? Uri.parse(
                'https://simert.transitoelguabo.gob.ec/api/gestion-usuarios/',
              ).replace(queryParameters: {'_tk': token})
            : Uri.parse(
                'https://simert.transitoelguabo.gob.ec/api/gestion-usuarios/',
              );

        final response = await HttpMonitorizado.get(
          uri,
          headers: {
            'Accept': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Token $token',
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map<String, dynamic>) continue;
              final id = item['id'] as int? ?? 0;
              if (id <= 0) continue;
              final username = (item['username'] as String? ?? '').trim();
              final first = (item['first_name'] as String? ?? '').trim();
              final last = (item['last_name'] as String? ?? '').trim();
              final full = '$first $last'.trim();
              mapa[id] = full.isNotEmpty ? full : username;
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _etiquetasUsuario
        ..clear()
        ..addAll(mapa);
    });
  }

  void _aplicarFiltros() {
    final filtradas = _todasNotificaciones.where((n) {
      final okUsuario =
          _filtroUsuario == 'todos' || n.usuario.toString() == _filtroUsuario;
      final okFecha = _coincideConRango(_fechaDeNotificacion(n));
      final placa = n.placa.toLowerCase();
      final okPlaca =
          _filtroPlaca.trim().isEmpty || placa.contains(_filtroPlaca);
      return okUsuario && okFecha && okPlaca;
    }).toList();

    final ordenadas = _ordenarLista(filtradas);
    if (!mounted) return;
    setState(() {
      _notificaciones = ordenadas;
      _grupos = _svc.agruparPorEstado(ordenadas);
    });
  }

  String _textoRango() {
    if (_fechaInicioFiltro == null || _fechaFinFiltro == null) {
      return 'Todas las fechas';
    }
    final ini = _formatoFechaSimple(_fechaInicioFiltro!);
    final fin = _formatoFechaSimple(_fechaFinFiltro!);
    return '$ini - $fin';
  }

  String _formatoFechaSimple(DateTime fecha) {
    final dd = fecha.day.toString().padLeft(2, '0');
    final mm = fecha.month.toString().padLeft(2, '0');
    final yyyy = fecha.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Future<List<Multa>> _obtenerCatalogoMultas() async {
    if (_catalogoMultas.isNotEmpty) return _catalogoMultas;

    try {
      final guardadas = await obtenerMultasGuardadas();
      if (guardadas.isNotEmpty) {
        _catalogoMultas = guardadas.where((m) => m.estado).toList();
      }
    } catch (_) {}

    try {
      final desdeApi = await fetchMultas();
      if (desdeApi.isNotEmpty) {
        await guardarMultasEnPreferencias(desdeApi);
        _catalogoMultas = desdeApi.where((m) => m.estado).toList();
      }
    } catch (_) {}

    return _catalogoMultas;
  }

  void _buscarPorPlaca() {
    setState(() {
      _filtroPlaca = _busquedaPlacaCtrl.text.trim().toLowerCase();
    });
    _aplicarFiltros();
  }

  Widget _buildFiltroPlaca() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CampoBusquedaApp(
        controller: _busquedaPlacaCtrl,
        hintText: 'Buscar por placa',
        labelText: 'Placa',
        textCapitalization: TextCapitalization.characters,
        onSearch: _buscarPorPlaca,
        onChanged: (_) => _buscarPorPlaca(),
        onClear: _buscarPorPlaca,
      ),
    );
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final op = prefs.getString('username') ?? 'OPERADOR';
    final userId = prefs.getInt('id') ?? 0;
    final esSuperuser = prefs.getBool('is_superuser') == true;

    _userId = userId;
    _esSuperuser = esSuperuser;

    if (_esSuperuser) {
      setState(() {
        _cargando = true;
        _error = null;
      });
      try {
        await _cargarEtiquetasUsuarios();
        var lista = await _svc.getTodasNotificacionesSistema();
        if (_mostrarSoloMesActual) {
          lista = _svc.filtrarNotificacionesMesActual(lista);
        }
        final ordenadas = _ordenarLista(lista);
        if (mounted) {
          setState(() {
            _operador = '${op.toUpperCase()} (ADMIN)';
            _todasNotificaciones = ordenadas;
            _cargando = false;
          });
          _aplicarFiltros();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e.toString();
            _cargando = false;
          });
        }
      }
      return;
    }

    if (_mostrarSoloMesActual) {
      // ── Caché primero: mostrar datos guardados al instante ────────────────
      final cached = await NotifMesCache.leer(userId);
      if (cached != null && cached.isNotEmpty) {
        final ordenadas = _ordenarLista(cached);
        if (mounted) {
          setState(() {
            _operador = op.toUpperCase();
            _todasNotificaciones = ordenadas;
            _cargando = false;
          });
          _aplicarFiltros();
        }
        // Actualizar en segundo plano sin mostrar spinner
        unawaited(_refrescarSilencioso(userId));
        return;
      }
    }

    // ── Sin caché: carga completa con indicador ───────────────────────────
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      List<Notificacion> lista;
      if (_mostrarSoloMesActual) {
        final todas = await _svc.getNotificaciones();
        lista = _svc.filtrarNotificacionesMesActual(todas);
        await NotifMesCache.guardar(userId, lista);
      } else {
        lista = await _svc.getTodasNotificacionesUsuario();
      }

      lista = _ordenarLista(lista);
      if (mounted) {
        setState(() {
          _operador = op.toUpperCase();
          _todasNotificaciones = lista;
          _cargando = false;
        });
        _aplicarFiltros();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  /// Consulta la API silenciosamente. Si hay diferencias respecto al caché
  /// (multas nuevas o cambios de estado), actualiza caché y refresca la UI.
  Future<void> _refrescarSilencioso(int userId) async {
    if (_esSuperuser) return;
    try {
      final todas = await _svc.getNotificaciones();
      final delMes = _svc.filtrarNotificacionesMesActual(todas);
      final enCache = await NotifMesCache.leer(userId) ?? [];
      if (NotifMesCache.tieneDiferencias(enCache, delMes)) {
        await NotifMesCache.guardar(userId, delMes);
        final ordenadas = _ordenarLista(delMes);
        if (mounted) {
          setState(() {
            _todasNotificaciones = ordenadas;
          });
          _aplicarFiltros();
        }
      }
    } catch (_) {
      // Silencioso — no interrumpir la experiencia del usuario
    }
  }

  void _suscribirWsNotificaciones() {
    final ws = ServicioWebSocket.instancia;
    ws.suscribir('notificaciones');

    _wsNotifSub?.cancel();
    _wsNotifSub = ws.escuchar('notificaciones').listen((evento) async {
      if (!mounted) return;
      if (evento.accion == 'snapshot' && evento.datos is List) {
        try {
          final lista = (evento.datos as List)
              .whereType<Map<String, dynamic>>()
              .map((j) => Notificacion.fromJson(j))
              .toList();
          final listaBase = _esSuperuser
              ? lista
              : lista.where((n) => n.usuario == _userId).toList();
          final delMes = _mostrarSoloMesActual
              ? _svc.filtrarNotificacionesMesActual(listaBase)
              : listaBase;
          final ordenadas = _ordenarLista(delMes);
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getInt('id') ?? 0;
          if (!_esSuperuser && _mostrarSoloMesActual && userId > 0) {
            unawaited(NotifMesCache.guardar(userId, delMes));
          }
          if (mounted) {
            setState(() {
              _todasNotificaciones = ordenadas;
              _cargando = false;
            });
            _aplicarFiltros();
          }
        } catch (_) {}
      } else if (evento.accion == 'create' && evento.datos is Map) {
        try {
          final nueva = Notificacion.fromJson(
            evento.datos as Map<String, dynamic>,
          );
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getInt('id') ?? 0;
          if (_esSuperuser || nueva.usuario == userId) {
            final actualizada = [nueva, ..._todasNotificaciones];
            final ordenadas = _ordenarLista(actualizada);
            if (!_esSuperuser && _mostrarSoloMesActual && userId > 0) {
              unawaited(NotifMesCache.guardar(userId, ordenadas));
            }
            if (mounted) {
              setState(() {
                _todasNotificaciones = ordenadas;
              });
              _aplicarFiltros();
            }
          }
        } catch (_) {}
      }
    });
  }

  void _alternarVista() {
    setState(() => _mostrarSoloMesActual = !_mostrarSoloMesActual);
    _cargar();
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
                    'Historial de Multas',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Muestra las multas pagadas, impagas e impugnadas organizadas por estado y período.',
                    style: const TextStyle(
                      color: AppColores.textoSecundario,
                      fontSize: 14,
                    ),
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

  void _mostrarDetalleMulta(Notificacion n, String tipo) {
    if (tipo == 'pagadas') return;

    final bool esImpugnada = tipo == 'impugnadas';
    final Color colorEstado = esImpugnada
        ? AppColores.info
        : AppColores.advertencia;
    final String estado = esImpugnada ? 'IMPUGNADA' : 'IMPAGA';
    final Future<Map<String, dynamic>?>? futuraEdicion = _esSuperuser
        ? _cargarDatosEdicionMulta(n)
        : null;

    String normalizar(String? valor) {
      final v = (valor ?? '').trim();
      if (v.isEmpty || v.toLowerCase() == 'n/a') return 'No disponible';
      return v;
    }

    String nombreCompleto() {
      final apellidos = (n.apellidos ?? '').trim();
      final nombre = n.nombres.trim();
      final full = '$nombre $apellidos'.trim();
      if (full.isEmpty || full.toLowerCase() == 'n/a') return 'No disponible';
      return full;
    }

    String textoCopia() {
      final buffer = StringBuffer()
        ..writeln('Multa N° ${normalizar(n.numero)}')
        ..writeln('Estado: $estado')
        ..writeln('Placa: ${normalizar(n.placa)}')
        ..writeln('Conductor: ${nombreCompleto()}')
        ..writeln('Cédula: ${normalizar(n.cedula)}')
        ..writeln('Ubicación: ${normalizar(n.ubicacion)}')
        ..writeln('Fecha emisión: ${_formatearFechaHora(n.fechaEmision)}')
        ..writeln('Comprobante: ${normalizar(n.numeroComprobante)}')
        ..writeln('Observación: ${normalizar(n.observacion)}');

      if (_esSuperuser) {
        buffer.writeln('Usuario emisor: ${_nombreUsuarioTarjeta(n.usuario)}');
      }

      if (esImpugnada) {
        buffer
          ..writeln('N° resolución: ${normalizar(n.numeroResolucion)}')
          ..writeln('Fecha resolución: ${normalizar(n.fechaResolucion)}')
          ..writeln('Resolución: ${normalizar(n.resolucion)}')
          ..writeln(
            'Obs. impugnación: ${normalizar(n.observacionImpugnacion)}',
          );
      }

      return buffer.toString().trim();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 46,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorEstado.withValues(alpha: 0.9),
                          colorEstado,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Detalle de multa',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: textoCopia()),
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Detalle copiado'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              tooltip: 'Copiar detalle',
                              icon: const Icon(
                                Icons.content_copy_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                estado,
                                style: TextStyle(
                                  color: colorEstado,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'N° ${normalizar(n.numero)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      children: [
                        _itemDetalle(
                          icono: Icons.directions_car_rounded,
                          etiqueta: 'Placa',
                          valor: normalizar(n.placa),
                        ),
                        _itemDetalle(
                          icono: Icons.person_rounded,
                          etiqueta: 'Conductor',
                          valor: nombreCompleto(),
                        ),
                        _itemDetalle(
                          icono: Icons.badge_rounded,
                          etiqueta: 'Cédula',
                          valor: normalizar(n.cedula),
                        ),
                        _itemDetalle(
                          icono: Icons.place_rounded,
                          etiqueta: 'Ubicación',
                          valor: normalizar(n.ubicacion),
                        ),
                        _itemDetalle(
                          icono: Icons.calendar_month_rounded,
                          etiqueta: 'Fecha de emisión',
                          valor: _formatearFechaHora(n.fechaEmision),
                        ),
                        _itemDetalle(
                          icono: Icons.receipt_long_rounded,
                          etiqueta: 'N° comprobante',
                          valor: normalizar(n.numeroComprobante),
                        ),
                        _itemDetalle(
                          icono: Icons.notes_rounded,
                          etiqueta: 'Observación',
                          valor: normalizar(n.observacion),
                          multilinea: true,
                        ),
                        if (_esSuperuser)
                          _itemDetalle(
                            icono: Icons.manage_accounts_rounded,
                            etiqueta: 'Usuario emisor',
                            valor: _nombreUsuarioTarjeta(n.usuario),
                          ),
                        if (_esSuperuser && futuraEdicion != null)
                          _buildPanelEdicionAdmin(futuraEdicion),
                        if (esImpugnada) ...[
                          _itemDetalle(
                            icono: Icons.rule_folder_rounded,
                            etiqueta: 'N° resolución',
                            valor: normalizar(n.numeroResolucion),
                          ),
                          _itemDetalle(
                            icono: Icons.event_note_rounded,
                            etiqueta: 'Fecha resolución',
                            valor: normalizar(n.fechaResolucion),
                          ),
                          _itemDetalle(
                            icono: Icons.description_rounded,
                            etiqueta: 'Resolución',
                            valor: normalizar(n.resolucion),
                            multilinea: true,
                          ),
                          _itemDetalle(
                            icono: Icons.gavel_rounded,
                            etiqueta: 'Observación impugnación',
                            valor: normalizar(n.observacionImpugnacion),
                            multilinea: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _itemDetalle({
    required IconData icono,
    required String etiqueta,
    required String valor,
    bool multilinea = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColores.acentoFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColores.borde),
      ),
      child: Row(
        crossAxisAlignment: multilinea
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icono, size: 18, color: AppColores.textoSecundario),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColores.textoTerciario,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColores.textoPrimario,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: multilinea ? null : 2,
                  overflow: multilinea ? null : TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _cargarDatosEdicionMulta(
    Notificacion notificacion,
  ) async {
    final detalle = await _svc.getDetallePorNotificacion(notificacion.id);
    if (detalle == null) return null;

    final catalogo = await _obtenerCatalogoMultas();
    if (catalogo.isEmpty) return null;

    final detalleId = detalle['id'] as int? ?? 0;
    if (detalleId <= 0) return null;

    final multaActual = detalle['multa'] as int? ?? catalogo.first.id;
    final totalActual =
        double.tryParse(detalle['total']?.toString() ?? '') ?? 0.0;

    return {
      'detalleId': detalleId,
      'multaId': multaActual,
      'total': totalActual,
      'catalogo': catalogo,
    };
  }

  Widget _buildPanelEdicionAdmin(Future<Map<String, dynamic>?> futureData) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: futureData,
      builder: (buildCtx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColores.acentoFondo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColores.borde),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Cargando edición de literal y valor...'),
              ],
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColores.acentoFondo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColores.borde),
            ),
            child: const Text(
              'No se pudo cargar el detalle editable de la multa.',
              style: TextStyle(
                color: AppColores.textoSecundario,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        final data = snapshot.data!;
        final detalleId = data['detalleId'] as int;
        final catalogo = data['catalogo'] as List<Multa>;
        if (catalogo.isEmpty) {
          return const SizedBox.shrink();
        }

        int multaSeleccionadaId = data['multaId'] as int;
        double valorSeleccionado = (data['total'] as double?) ?? 0.0;
        bool guardando = false;

        Multa multaActual = catalogo.firstWhere(
          (m) => m.id == multaSeleccionadaId,
          orElse: () => catalogo.first,
        );
        if (valorSeleccionado <= 0) {
          valorSeleccionado = multaActual.valor;
        }

        return StatefulBuilder(
          builder: (localCtx, setLocalState) {
            multaActual = catalogo.firstWhere(
              (m) => m.id == multaSeleccionadaId,
              orElse: () => catalogo.first,
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColores.acentoFondo,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColores.borde),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Editar característica de multa',
                          style: TextStyle(
                            color: AppColores.textoSecundario,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColores.acentoAdmin.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColores.acentoAdmin.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_rounded,
                              size: 12,
                              color: AppColores.acentoAdmin,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Solo administrador',
                              style: TextStyle(
                                color: AppColores.acentoAdmin,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: multaSeleccionadaId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Literal',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColores.borde),
                      ),
                    ),
                    items: catalogo
                        .map(
                          (m) => DropdownMenuItem<int>(
                            value: m.id,
                            child: Text(
                              '${m.tipo} - ${m.detalleMulta}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: guardando
                        ? null
                        : (value) {
                            if (value == null) return;
                            final seleccionada = catalogo.firstWhere(
                              (m) => m.id == value,
                              orElse: () => catalogo.first,
                            );
                            setLocalState(() {
                              multaSeleccionadaId = value;
                              valorSeleccionado = seleccionada.valor;
                            });
                          },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColores.borde),
                    ),
                    child: Text(
                      'Valor: USD ${valorSeleccionado.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColores.textoPrimario,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: guardando
                          ? null
                          : () async {
                              final navigator = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);
                              setLocalState(() => guardando = true);
                              try {
                                await _svc.actualizarCaracteristicasMulta(
                                  detalleId: detalleId,
                                  multaId: multaSeleccionadaId,
                                  total: valorSeleccionado,
                                );
                                if (!mounted) return;
                                await _cargar();
                                if (navigator.canPop()) {
                                  navigator.pop();
                                }
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Multa actualizada correctamente',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('No se pudo actualizar: $e'),
                                  ),
                                );
                              } finally {
                                if (mounted) {
                                  setLocalState(() => guardando = false);
                                }
                              }
                            },
                      icon: guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(
                        guardando ? 'Guardando...' : 'Guardar cambios',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.acentoAdmin,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: _buildAppBar(), body: _buildBody());
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final pagadas = _grupos['pagadas']!.length;
    final impagas = _grupos['impagas']!.length;
    final impugnadas = _grupos['impugnadas']!.length;

    return AppBar(
      centerTitle: true,
      title: Text(
        _esSuperuser
            ? (_mostrarSoloMesActual
                  ? 'Multas del Mes (Global)'
                  : 'Historial Global')
            : (_mostrarSoloMesActual
                  ? 'Multas del Mes'
                  : 'Historial de Multas'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          tooltip: 'Información',
          onPressed: () => _mostrarInfo(context),
        ),
        IconButton(
          icon: Icon(
            _mostrarSoloMesActual ? Icons.history : Icons.calendar_month,
            color: Colors.white,
          ),
          tooltip: _mostrarSoloMesActual
              ? 'Ver historial completo'
              : 'Ver solo este mes',
          onPressed: _alternarVista,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Actualizar',
          onPressed: _cargar,
        ),
        if (_esSuperuser)
          IconButton(
            icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.white),
            tooltip: 'Limpiar filtros',
            onPressed: () {
              setState(() {
                _filtroUsuario = 'todos';
                _filtroPlaca = '';
                _busquedaPlacaCtrl.clear();
                _fechaInicioFiltro = null;
                _fechaFinFiltro = null;
              });
              _aplicarFiltros();
            },
          ),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: AppColores.gradientePrincipal,
        ),
      ),
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        tabs: [
          _buildTab(Icons.check_circle_outline, 'Pagadas', pagadas),
          _buildTab(Icons.pending_outlined, 'Impagas', impagas),
          _buildTab(Icons.gavel_outlined, 'Impugnadas', impugnadas),
        ],
      ),
    );
  }

  Tab _buildTab(IconData icon, String label, int count) {
    return Tab(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15),
          const SizedBox(height: 2),
          Text('$label ($count)', style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Body ─────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_cargando) return _buildCargando();
    if (_error != null) return _buildError();

    final contenido = _notificaciones.isEmpty
        ? _buildVacio()
        : TabBarView(
            controller: _tabController,
            children: [
              _buildLista(_grupos['pagadas']!, 'pagadas'),
              _buildLista(_grupos['impagas']!, 'impagas'),
              _buildLista(_grupos['impugnadas']!, 'impugnadas'),
            ],
          );

    if (!_esSuperuser) {
      return Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: _buildFiltroPlaca(),
          ),
          Expanded(child: contenido),
        ],
      );
    }

    return Column(
      children: [
        _buildFiltrosAdmin(),
        Expanded(child: contenido),
      ],
    );
  }

  Widget _buildFiltrosAdmin() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          _buildFiltroPlaca(),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filtroUsuario,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Seleccionar usuario',
                    filled: true,
                    fillColor: AppColores.acentoFondo,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColores.borde),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColores.acentoAdmin,
                        width: 2,
                      ),
                    ),
                    prefixIcon: const Icon(
                      Icons.person_search_rounded,
                      color: AppColores.acentoAdmin,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'todos',
                      child: Text('Todos los usuarios'),
                    ),
                    ..._usuariosDisponibles.map(
                      (id) => DropdownMenuItem<String>(
                        value: id.toString(),
                        child: Text(
                          _nombreUsuario(id),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _filtroUsuario = value ?? 'todos';
                    });
                    _aplicarFiltros();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final hoy = DateTime.now();
                    final inicial = DateTimeRange(
                      start:
                          _fechaInicioFiltro ??
                          DateTime(hoy.year, hoy.month, 1),
                      end: _fechaFinFiltro ?? hoy,
                    );
                    final rango = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(hoy.year + 1),
                      initialDateRange: inicial,
                      helpText: 'Filtrar por rango de fechas',
                      locale: const Locale('es', 'ES'),
                    );
                    if (rango == null) return;
                    setState(() {
                      _fechaInicioFiltro = rango.start;
                      _fechaFinFiltro = rango.end;
                    });
                    _aplicarFiltros();
                  },
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(_textoRango(), overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _colorPrimario,
                    side: BorderSide(
                      color: _colorPrimario.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColores.acentoFondo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_notificaciones.length} resultados',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColores.textoSecundario,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_usuariosDisponibles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_usuariosDisponibles.length} usuarios disponibles para filtrar',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColores.textoTerciario,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Loading / Error / Empty ───────────────────────────────────────────────
  Widget _buildCargando() {
    return const EstadoCargaApp(
      icono: Icons.notifications_active_rounded,
      mensaje: 'Cargando notificaciones...',
      colorInicio: _colorPrimario,
      colorFin: _colorSecundario,
    );
  }

  Widget _buildError() {
    String msg = _error ?? 'Error desconocido';
    if (msg.contains('Null is not a subtype')) {
      msg = 'Error en el formato de datos recibidos.';
    } else if (msg.contains('No se encontró el ID')) {
      msg = 'Sesión expirada. Por favor inicie sesión nuevamente.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColores.error.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: AppColores.error.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColores.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  color: AppColores.error,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Error al cargar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _colorTexto,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColores.error, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorPrimario,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _colorPrimario.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              color: _colorPrimario,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _mostrarSoloMesActual
                ? (_esSuperuser
                      ? 'Sin multas en este mes para el filtro actual'
                      : 'Sin multas este mes')
                : (_esSuperuser
                      ? 'Sin multas para el filtro actual'
                      : 'Sin multas registradas'),
            style: const TextStyle(
              color: _colorPrimario,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _operador,
            style: const TextStyle(
              color: AppColores.textoTerciario,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Lista ────────────────────────────────────────────────────────────────
  Widget _buildLista(List<Notificacion> lista, String tipo) {
    if (lista.isEmpty) return _buildVacioTab(tipo);

    return RefreshIndicator(
      color: _colorPrimario,
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: lista.length,
        itemBuilder: (_, i) => _buildCard(lista[i], tipo),
      ),
    );
  }

  Widget _buildVacioTab(String tipo) {
    final IconData icon;
    final String msg;
    final Color color;

    switch (tipo) {
      case 'pagadas':
        icon = Icons.check_circle_outline;
        msg = 'Sin multas pagadas';
        color = AppColores.exito;
        break;
      case 'impagas':
        icon = Icons.pending_outlined;
        msg = 'Sin multas pendientes';
        color = AppColores.advertencia;
        break;
      default:
        icon = Icons.gavel_outlined;
        msg = 'Sin multas impugnadas';
        color = AppColores.info;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            msg,
            style: const TextStyle(
              color: _colorTexto,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Card ─────────────────────────────────────────────────────────────────
  Widget _buildCard(Notificacion n, String tipo) {
    final bool abreDetalle = tipo != 'pagadas';
    final Color badgeColor;
    final String badgeText;
    final IconData badgeIcon;

    switch (tipo) {
      case 'pagadas':
        badgeColor = AppColores.exito;
        badgeText = 'PAGADO';
        badgeIcon = Icons.check_circle;
        break;
      case 'impagas':
        badgeColor = AppColores.advertencia;
        badgeText = 'IMPAGO';
        badgeIcon = Icons.schedule;
        break;
      default:
        badgeColor = AppColores.info;
        badgeText = 'IMPUGNADO';
        badgeIcon = Icons.gavel;
    }

    final fechaHora = _formatearFechaHora(n.fechaEmision);
    final inicial = n.placa.isNotEmpty ? n.placa[0].toUpperCase() : '?';

    return TarjetaListaApp(
      colorAcento: badgeColor,
      avatar: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Text(
            inicial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ),
      titulo: n.placa,
      subtitulo: n.nombres,
      encabezadoDerecha: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(badgeIcon, color: badgeColor, size: 14),
      ),
      cuerpo: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fechaHora,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColores.textoTerciario,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (_esSuperuser)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _nombreUsuarioTarjeta(n.usuario),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColores.textoSecundario,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, color: badgeColor, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColores.acentoFondo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'N° ${n.numero}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColores.textoSecundario,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (abreDetalle)
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColores.textoTerciario,
              size: 20,
            ),
        ],
      ),
      onTap: abreDetalle ? () => _mostrarDetalleMulta(n, tipo) : null,
    );
  }

  String _formatearFechaHora(String fechaStr) {
    try {
      final fecha = DateTime.parse(fechaStr).toLocal();
      final dd = fecha.day.toString().padLeft(2, '0');
      final mm = fecha.month.toString().padLeft(2, '0');
      final yyyy = fecha.year.toString();
      final hh = fecha.hour.toString().padLeft(2, '0');
      final min = fecha.minute.toString().padLeft(2, '0');
      return '$dd/$mm/$yyyy $hh:$min';
    } catch (_) {
      return fechaStr;
    }
  }
}

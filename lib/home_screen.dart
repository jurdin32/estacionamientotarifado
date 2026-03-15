import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:estacionamientotarifado/consultas/consultar_multas.dart';
import 'package:estacionamientotarifado/consultas/credencial.dart';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart'
    as svc2;
import 'package:estacionamientotarifado/tarjetas/views/EstacionamientoScreen.dart';
import 'package:estacionamientotarifado/tarjetas/views/NotificacionScreen.dart';
import 'package:estacionamientotarifado/tarjetas/views/Notificacionusuario.dart';
import 'package:estacionamientotarifado/admin/estaciones_screen.dart';
import 'package:estacionamientotarifado/consultas/admin_usuarios_screen.dart';
import 'package:estacionamientotarifado/consultas/cambiar_contrasena.dart';
import 'package:estacionamientotarifado/consultas/personas_registradas_screen.dart';
import 'package:estacionamientotarifado/consultas/vehicle_screen.dart';
import 'package:estacionamientotarifado/login_screan.dart';
import 'package:estacionamientotarifado/servicios/servicioPermisos.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  int usuario_id = 0;
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

  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _loadUserData();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
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
      usuario_id = uid;
      lastLogin = _formatDate(prefs.getString('last_login') ?? '');
      _isSuperuser = superuser;
      _permisos = permisos;
    });
    _cargarMetricas();
    // Pre-calentar cachés en segundo plano
    final token = prefs.getString('token') ?? '';
    final cookie = prefs.getString('session_cookie') ?? '';
    EstacionesAdminScreen.preWarmCache(token: token, sessionCookie: cookie);
    Notificacionesscreen.preWarmCache();
    NotificacionesUsuarioScreen.preWarmCache(uid);
    AdminUsuariosScreen.preWarmCache(token: token, sessionCookie: cookie);
  }

  bool _permitido(String key) {
    if (_isSuperuser) return true;
    return _permisos[key] ?? true;
  }

  Future<void> _cargarMetricas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final uid = prefs.getInt('id') ?? 0;
      final now = DateTime.now();

      Uri uriTk(String path) {
        final base = 'https://simert.transitoelguabo.gob.ec$path';
        return token.isNotEmpty
            ? Uri.parse(base).replace(queryParameters: {'_tk': token})
            : Uri.parse(base);
      }

      // ── Multas ────────────────────────────────────────────────────────
      List<Map<String, dynamic>> multas =
          await svc2.CacheDetallesService.leerMes();

      // Si la caché de notificaciones está vacía, intentar caché local de multas
      if (multas.isEmpty) {
        final multasRaw = prefs.getString('multas');
        if (multasRaw != null) {
          try {
            multas = (json.decode(multasRaw) as List)
                .whereType<Map<String, dynamic>>()
                .toList();
          } catch (_) {}
        }
      }

      // Si aún vacío, consultar API con token
      if (multas.isEmpty && token.isNotEmpty) {
        try {
          final resp = await http.get(uriTk('/api/details_multas'));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            if (data is List) {
              multas = data.whereType<Map<String, dynamic>>().toList();
            } else if (data is Map && data['results'] is List) {
              multas = (data['results'] as List)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }
            if (multas.isNotEmpty) {
              await prefs.setString('multas', json.encode(multas));
            }
          }
        } catch (_) {}
      }

      // Filtrar multas del mes actual
      final multasMes = multas.where((m) {
        try {
          final dt = DateTime.parse(m['fechaEmision'] as String);
          return dt.year == now.year && dt.month == now.month;
        } catch (_) {
          return false;
        }
      }).toList();
      final multasHoy = multasMes.where((m) {
        try {
          final dt = DateTime.parse(m['fechaEmision'] as String);
          return dt.day == now.day;
        } catch (_) {
          return false;
        }
      }).length;

      // ── Tarjetas ──────────────────────────────────────────────────────
      List<Map<String, dynamic>> tarjetas = [];
      final cached = prefs.getString('estacionamientos_tarjeta');
      if (cached != null) {
        try {
          tarjetas = (json.decode(cached) as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        } catch (_) {}
      }

      // Si no hay caché, consultar API con token
      if (tarjetas.isEmpty && token.isNotEmpty) {
        try {
          final resp = await http.get(uriTk('/api/est_tarjeta/'));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            if (data is List) {
              tarjetas = data.whereType<Map<String, dynamic>>().toList();
            } else if (data is Map && data['results'] is List) {
              tarjetas = (data['results'] as List)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }
            if (tarjetas.isNotEmpty) {
              await prefs.setString(
                'estacionamientos_tarjeta',
                json.encode(tarjetas),
              );
            }
          }
        } catch (_) {}
      }

      // Filtrar por usuario (superadmin ve todos; usuario normal ve solo los suyos)
      final tarjetasUsuario = _isSuperuser
          ? tarjetas
          : tarjetas.where((t) => (t['usuario'] as int?) == uid).toList();

      final tarjetasMes = tarjetasUsuario.where((t) {
        try {
          final dt = DateTime.parse(t['fecha'] as String);
          return dt.year == now.year && dt.month == now.month;
        } catch (_) {
          return false;
        }
      }).toList();
      final tarjetasHoy = tarjetasMes.where((t) {
        try {
          final dt = DateTime.parse(t['fecha'] as String);
          return dt.day == now.day;
        } catch (_) {
          return false;
        }
      }).length;
      final placasUnicas = tarjetasMes
          .map((t) => t['placa'] as String? ?? '')
          .toSet()
          .where((p) => p.isNotEmpty)
          .length;

      if (mounted) {
        setState(() {
          _totalMultasMes = multasMes.length;
          _multasHoy = multasHoy;
          _tarjetasMes = tarjetasMes.length;
          _tarjetasHoy = tarjetasHoy;
          _placasUnicasMes = placasUnicas;
          _metricasCargadas = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _metricasCargadas = true);
    }
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = (MediaQuery.of(context).size.width / 400).clamp(
      0.8,
      1.3,
    );
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text('Bienvenido'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: _buildDrawer(context, scale),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo degradado con formas decorativas
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -size.width * .2,
            left: -size.width * .25,
            child: Transform.rotate(
              angle: -0.4,
              child: Container(
                width: size.width * .7,
                height: size.width * .7,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
            ),
          ),
          Positioned(
            right: -size.width * .2,
            bottom: -size.width * .25,
            child: Transform.rotate(
              angle: 0.8,
              child: Container(
                width: size.width * .9,
                height: size.width * .9,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(200),
                ),
              ),
            ),
          ),
          // Contenido central
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 24 * scale,
                  vertical: 20 * scale,
                ),
                child: Column(
                  children: [
                    SizedBox(height: 12 * scale),
                    // Avatar
                    CircleAvatar(
                      radius: 48 * scale,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : "U",
                        style: TextStyle(
                          fontSize: 34 * scale,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    Text(
                      name.isNotEmpty ? "👋 $name!" : "Bienvenido 👋",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      "@$username",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14 * scale,
                      ),
                    ),
                    SizedBox(height: 20 * scale),
                    // Tarjetas info
                    _infoCard(Icons.email, "Correo", email, scale),
                    SizedBox(height: 10 * scale),
                    _infoCard(
                      Icons.access_time,
                      "Último acceso",
                      lastLogin,
                      scale,
                    ),
                    SizedBox(height: 20 * scale),
                    // ── Métricas del mes ──────────────────────────────────
                    _buildMetricas(scale),
                    SizedBox(height: 16 * scale),
                    // Indicativo
                    Text(
                      "Usa el menú lateral para navegar 🔍",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13 * scale,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    SizedBox(height: 10 * scale),
                    Text(
                      'v0.0.1 - 2026',
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

  // Drawer lateral
  Drawer _buildDrawer(BuildContext context, double scale) {
    return Drawer(
      backgroundColor: const Color(0xFFF0F4FF),
      child: Column(
        children: [
          // ── Header con gradiente ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 48 * scale, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                          color: Color(0xFF5E17EB),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ADMINISTRACIÓN',
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF5E17EB),
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
              'v0.0.1 - 2026',
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

  // Tarjeta tipo glass - tamaño aumentado
  Widget _infoCard(IconData icon, String title, String value, double scale) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: 16 * scale,
            horizontal: 20 * scale,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24 * scale),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      value.isEmpty ? "No disponible" : value,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        ? const Color(0xFF5E17EB)
        : const Color(0xFF5E17EB);
    final iconBg = isLogout
        ? Colors.red.shade50
        : isAdmin
        ? const Color(0xFF5E17EB).withValues(alpha: 0.15)
        : const Color(0xFF5E17EB).withValues(alpha: 0.10);
    final textColor = isLogout
        ? Colors.red.shade600
        : isAdmin
        ? const Color(0xFF5E17EB)
        : const Color(0xFF001F54);

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

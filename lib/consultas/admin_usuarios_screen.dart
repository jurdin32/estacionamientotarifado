import 'package:estacionamientotarifado/servicios/servicioPermisos.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AdminUsuariosScreen extends StatefulWidget {
  const AdminUsuariosScreen({super.key});

  /// Pre-calienta el caché de usuarios desde HomeScreen.
  static Future<void> preWarmCache({
    required String token,
    String sessionCookie = '',
  }) async {
    // Si ya hay caché, no hacer nada
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_admin_usuarios');
    if (raw != null && raw.isNotEmpty) return;
    try {
      final Uri uri;
      final base =
          'https://simert.transitoelguabo.gob.ec/api/gestion-usuarios/';
      if (token.isNotEmpty) {
        uri = Uri.parse(base).replace(queryParameters: {'_tk': token.trim()});
      } else {
        uri = Uri.parse(base);
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Token ${token.trim()}',
        if (sessionCookie.isNotEmpty) 'Cookie': sessionCookie,
      };
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<Map<String, dynamic>> lista = [];
        if (data is List) {
          lista = data.whereType<Map<String, dynamic>>().toList();
        } else if (data is Map && data['results'] is List) {
          lista = (data['results'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        } else if (data is Map && data['data'] is List) {
          lista = (data['data'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
        final clean = lista.map((u) {
          final copy = Map<String, dynamic>.from(u)..remove('_nombre');
          return copy;
        }).toList();
        await prefs.setString('cache_admin_usuarios', json.encode(clean));
      }
    } catch (_) {
      // Silencioso — se cargará al entrar a la pantalla
    }
  }

  @override
  State<AdminUsuariosScreen> createState() => _AdminUsuariosScreenState();
}

class _AdminUsuariosScreenState extends State<AdminUsuariosScreen> {
  static const Color _colorPrimario = Color(0xFF001F54);
  static const Color _colorSecundario = Color(0xFF5E17EB);
  static const Color _colorFondo = Color(0xFFF0F4FF);
  static const Color _colorSubtexto = Color(0xFF555555);

  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _filtrados = [];
  String _filtroTipo =
      'todos'; // 'todos' | 'habilitados' | 'deshabilitados' | 'admins'
  String? _token;
  String _sessionCookie = '';

  // Permisos cargados por usuario: userId -> Map<key, bool>
  final Map<int, Map<String, bool>> _permisosCache = {};
  // Estado habilitado/deshabilitado por userId
  final Map<int, bool> _activosCache = {};
  // IDs que están siendo actualizados
  final Set<int> _toggling = {};

  // ID del usuario actualmente logueado
  int _miId = 0;

  static const String _kCacheUsuarios = 'cache_admin_usuarios';

  @override
  void initState() {
    super.initState();
    _init();
    _searchCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_filtrar);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _sessionCookie = prefs.getString('session_cookie') ?? '';
    _miId = prefs.getInt('id') ?? 0;
    final tieneCahe = await _cargarDesdeCache();
    if (!tieneCahe) await _fetchUsuarios();
  }

  Future<void> _guardarCache(List<Map<String, dynamic>> lista) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = lista.map((u) {
        final copy = Map<String, dynamic>.from(u)..remove('_nombre');
        return copy;
      }).toList();
      await prefs.setString(_kCacheUsuarios, json.encode(clean));
    } catch (_) {}
  }

  Future<bool> _cargarDesdeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheUsuarios);
      if (raw == null || raw.isEmpty) return false;
      final data = json.decode(raw);
      if (data is! List) return false;
      final lista = data.whereType<Map<String, dynamic>>().toList();
      for (final u in lista) {
        final first = (u['first_name'] as String? ?? '').trim();
        final last = (u['last_name'] as String? ?? '').trim();
        u['_nombre'] = '$first $last'.trim();
      }
      if (mounted) {
        setState(() {
          _usuarios = lista;
          _filtrados = lista;
        });
      }
      // Cargar permisos en paralelo (mucho más rápido que secuencial)
      await Future.wait(
        lista.map((u) async {
          final uid = (u['id'] as int?) ?? 0;
          _permisosCache[uid] = await PermissionsService.getPermisos(uid);
          _activosCache[uid] = u['is_active'] as bool? ?? true;
        }),
      );
      if (mounted) setState(() {});
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      // Nota: Apache/mod_wsgi elimina Authorization; se usa _tk en query param.
      if (_token != null && _token!.isNotEmpty)
        'Authorization': 'Token ${_token!.trim()}',
      if (_sessionCookie.isNotEmpty) 'Cookie': _sessionCookie,
    };
  }

  /// Devuelve la URI con el token como query param ?_tk=
  /// (workaround: Apache elimina el header Authorization antes de llegar a Django).
  Uri _uriConToken(String path) {
    final base = 'https://simert.transitoelguabo.gob.ec$path';
    if (_token != null && _token!.isNotEmpty) {
      return Uri.parse(base).replace(queryParameters: {'_tk': _token!.trim()});
    }
    return Uri.parse(base);
  }

  Future<void> _fetchUsuarios() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      debugPrint(
        '[AdminUsuarios] sessionCookie=${_sessionCookie.isNotEmpty ? _sessionCookie.substring(0, _sessionCookie.length.clamp(0, 60)) : "VACÍA"} token=${_token?.isNotEmpty == true ? "presente" : "AUSENTE"}',
      );

      final uri = _uriConToken('/api/gestion-usuarios/');
      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 30));
      debugPrint('[AdminUsuarios] headers enviados: ${_buildHeaders()}');
      debugPrint(
        '[AdminUsuarios] status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}',
      );
      debugPrint('[AdminUsuarios] response headers: ${response.headers}');

      if (response.statusCode != 200) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'Error ${response.statusCode}\n${response.body.length > 300 ? response.body.substring(0, 300) : response.body}',
          );
        }
        return;
      }

      final data = json.decode(response.body);
      List<Map<String, dynamic>> lista = [];
      if (data is List) {
        lista = data.whereType<Map<String, dynamic>>().toList();
      } else if (data is Map && data['results'] is List) {
        lista = (data['results'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      } else if (data is Map && data['data'] is List) {
        lista = (data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      debugPrint('[AdminUsuarios] usuarios parseados: ${lista.length}');

      // Normalizar nombre completo para facilitar búsqueda
      for (final u in lista) {
        final first = (u['first_name'] as String? ?? '').trim();
        final last = (u['last_name'] as String? ?? '').trim();
        u['_nombre'] = '$first $last'.trim();
      }
      if (mounted) {
        setState(() {
          _usuarios = lista;
          _filtrados = lista;
        });
      }
      // Pre-cargar permisos y estado activo en paralelo
      await Future.wait(
        lista.map((u) async {
          final uid = (u['id'] as int?) ?? 0;
          _permisosCache[uid] = await PermissionsService.getPermisos(uid);
          _activosCache[uid] = u['is_active'] as bool? ?? true;
        }),
      );
      await _guardarCache(lista);
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('[AdminUsuarios] excepción: $e\n$st');
      if (mounted) {
        setState(() => _errorMessage = 'Error de red: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleActivo(
    int userId,
    String nombre,
    bool valorActual,
  ) async {
    final nuevoValor = !valorActual;
    final accion = nuevoValor ? 'habilitar' : 'deshabilitar';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              nuevoValor ? Icons.check_circle_rounded : Icons.block_rounded,
              color: nuevoValor ? Colors.green.shade600 : Colors.red.shade600,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              nuevoValor ? 'Habilitar usuario' : 'Deshabilitar usuario',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        content: Text('¿Deseas $accion al usuario "$nombre"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: nuevoValor
                  ? Colors.green.shade600
                  : Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(nuevoValor ? 'Habilitar' : 'Deshabilitar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _toggling.add(userId));
    try {
      final uri = _uriConToken('/api/gestion-usuarios/$userId/');
      final response = await http.patch(
        uri,
        headers: _buildHeaders(),
        body: json.encode({'is_active': nuevoValor}),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        _activosCache[userId] = nuevoValor;
        for (final lista in [_usuarios, _filtrados]) {
          final idx = lista.indexWhere((u) => (u['id'] as int?) == userId);
          if (idx != -1) lista[idx]['is_active'] = nuevoValor;
        }
        await _guardarCache(_usuarios);
        // Si el usuario modificado es el logueado, actualizar sus prefs
        if (userId == _miId) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_active', nuevoValor);
        }
        if (mounted) setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Usuario ${nuevoValor ? 'habilitado' : 'deshabilitado'} correctamente.',
              ),

              backgroundColor: nuevoValor
                  ? Colors.green.shade700
                  : Colors.red.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al actualizar (${response.statusCode}).'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(userId));
    }
  }

  Future<void> _cambiarTipoUsuario(
    int userId,
    String nombre,
    bool nuevoAdmin,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.manage_accounts_rounded,
              color: _colorPrimario,
              size: 22,
            ),
            SizedBox(width: 10),
            Text('Cambiar tipo de usuario', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          nuevoAdmin
              ? '¿Otorgar permisos de Superadministrador a "$nombre"?\nTendrá acceso total.'
              : '¿Quitar privilegios administrativos a "$nombre"?\nPasará a ser usuario normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _colorPrimario,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _toggling.add(userId));
    try {
      final uri = _uriConToken('/api/gestion-usuarios/$userId/');
      final response = await http.patch(
        uri,
        headers: _buildHeaders(),
        body: json.encode({'is_superuser': nuevoAdmin, 'is_staff': nuevoAdmin}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        for (final lista in [_usuarios, _filtrados]) {
          final idx = lista.indexWhere((u) => (u['id'] as int?) == userId);
          if (idx != -1) {
            lista[idx]['is_superuser'] = nuevoAdmin;
            lista[idx]['is_staff'] = nuevoAdmin;
          }
        }
        await _guardarCache(_usuarios);
        // Si el usuario modificado es el logueado, actualizar sus prefs
        if (userId == _miId) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_superuser', nuevoAdmin);
        }
        if (mounted) setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Tipo de usuario actualizado.'),

              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al actualizar (${response.statusCode}).'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(userId));
    }
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────

  Widget _seccionTitulo(String titulo, IconData icono) {
    return Row(
      children: [
        Icon(icono, size: 16, color: _colorSecundario),
        const SizedBox(width: 6),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _colorPrimario,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
      ],
    );
  }

  Widget _campoFormulario(
    TextEditingController ctrl,
    String etiqueta,
    IconData icono, {
    bool requerido = false,
    bool obscure = false,
    TextInputType tipo = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: tipo,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: etiqueta,
        prefixIcon: Icon(icono, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
      validator: requerido
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null
          : null,
    );
  }

  Future<void> _crearUsuario() async {
    final fnCtrl = TextEditingController();
    final lnCtrl = TextEditingController();
    final usCtrl = TextEditingController();
    final emCtrl = TextEditingController();
    final pwCtrl = TextEditingController();
    final pw2Ctrl = TextEditingController();
    bool esSuperadmin = false;
    bool obscurePw = true;
    bool obscurePw2 = true;
    final formKey = GlobalKey<FormState>();

    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final inicial = fnCtrl.text.isNotEmpty
              ? fnCtrl.text[0].toUpperCase()
              : usCtrl.text.isNotEmpty
              ? usCtrl.text[0].toUpperCase()
              : '+';

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.9,
              maxChildSize: 0.97,
              minChildSize: 0.6,
              expand: false,
              builder: (_, scrollCtrl) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Header degradado
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            child: Text(
                              inicial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nuevo usuario',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Completa los datos para crear la cuenta',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Formulario
                    Expanded(
                      child: Form(
                        key: formKey,
                        child: ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          children: [
                            // Sección: Datos personales
                            _seccionTitulo(
                              'Datos personales',
                              Icons.person_rounded,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _campoFormulario(
                                    fnCtrl,
                                    'Nombre',
                                    Icons.badge_outlined,
                                    onChanged: (_) => setSt(() {}),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _campoFormulario(
                                    lnCtrl,
                                    'Apellido',
                                    Icons.badge_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _campoFormulario(
                              usCtrl,
                              'Nombre de usuario',
                              Icons.account_circle_outlined,
                              requerido: true,
                              onChanged: (_) => setSt(() {}),
                            ),
                            const SizedBox(height: 14),
                            _campoFormulario(
                              emCtrl,
                              'Email',
                              Icons.email_outlined,
                              tipo: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 22),
                            // Sección: Seguridad
                            _seccionTitulo('Contraseña', Icons.lock_rounded),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: pwCtrl,
                              obscureText: obscurePw,
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePw
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () =>
                                      setSt(() => obscurePw = !obscurePw),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 12,
                                ),
                              ),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'La contraseña es requerida'
                                  : v.length < 6
                                  ? 'Mínimo 6 caracteres'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: pw2Ctrl,
                              obscureText: obscurePw2,
                              decoration: InputDecoration(
                                labelText: 'Confirmar contraseña',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscurePw2
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () =>
                                      setSt(() => obscurePw2 = !obscurePw2),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 12,
                                ),
                              ),
                              validator: (v) => v != pwCtrl.text
                                  ? 'Las contraseñas no coinciden'
                                  : null,
                            ),
                            const SizedBox(height: 22),
                            // Sección: Rol
                            _seccionTitulo(
                              'Rol de la cuenta',
                              Icons.admin_panel_settings_rounded,
                            ),
                            const SizedBox(height: 12),
                            // Chips de selección de rol
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setSt(() => esSuperadmin = false),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: !esSuperadmin
                                            ? Colors.blueGrey.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: !esSuperadmin
                                              ? Colors.blueGrey
                                              : Colors.grey.shade300,
                                          width: !esSuperadmin ? 1.8 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.person_rounded,
                                            size: 28,
                                            color: !esSuperadmin
                                                ? Colors.blueGrey
                                                : Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Normal',
                                            style: TextStyle(
                                              fontWeight: !esSuperadmin
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: !esSuperadmin
                                                  ? Colors.blueGrey.shade700
                                                  : Colors.grey.shade500,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Acceso según permisos',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setSt(() => esSuperadmin = true),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: esSuperadmin
                                            ? Colors.amber.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: esSuperadmin
                                              ? Colors.amber.shade700
                                              : Colors.grey.shade300,
                                          width: esSuperadmin ? 1.8 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.shield_rounded,
                                            size: 28,
                                            color: esSuperadmin
                                                ? Colors.amber.shade700
                                                : Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Superadmin',
                                            style: TextStyle(
                                              fontWeight: esSuperadmin
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: esSuperadmin
                                                  ? Colors.amber.shade800
                                                  : Colors.grey.shade500,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Acceso total al sistema',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            // Botón crear
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _colorPrimario,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 2,
                                ),
                                onPressed: () {
                                  if (formKey.currentState!.validate()) {
                                    Navigator.pop(ctx, true);
                                  }
                                },
                                icon: const Icon(
                                  Icons.person_add_rounded,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Crear usuario',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (confirmar != true) return;
    setState(() => _isLoading = true);
    try {
      final uri = _uriConToken('/api/gestion-usuarios/');
      final response = await http.post(
        uri,
        headers: _buildHeaders(),
        body: json.encode({
          'first_name': fnCtrl.text.trim(),
          'last_name': lnCtrl.text.trim(),
          'username': usCtrl.text.trim(),
          'email': emCtrl.text.trim(),
          'password': pwCtrl.text,
          'is_superuser': esSuperadmin,
          'is_staff': esSuperadmin,
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Usuario "${usCtrl.text.trim()}" creado.'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        await _fetchUsuarios();
      } else {
        final msg = response.body.length > 150
            ? response.body.substring(0, 150)
            : response.body;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error ${response.statusCode}: $msg'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editarUsuario(Map<String, dynamic> usuario) async {
    final uid = (usuario['id'] as int?) ?? 0;
    final fnCtrl = TextEditingController(
      text: usuario['first_name'] as String? ?? '',
    );
    final lnCtrl = TextEditingController(
      text: usuario['last_name'] as String? ?? '',
    );
    final emCtrl = TextEditingController(
      text: usuario['email'] as String? ?? '',
    );
    final pwCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: _colorPrimario, size: 22),
            SizedBox(width: 10),
            Text('Editar usuario', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _campoFormulario(
                        fnCtrl,
                        'Nombre',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _campoFormulario(
                        lnCtrl,
                        'Apellido',
                        Icons.person_outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _campoFormulario(
                  emCtrl,
                  'Email',
                  Icons.email_outlined,
                  tipo: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                _campoFormulario(
                  pwCtrl,
                  'Nueva contraseña (opcional)',
                  Icons.lock_outline,
                  obscure: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _colorPrimario,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final body = <String, dynamic>{
      'first_name': fnCtrl.text.trim(),
      'last_name': lnCtrl.text.trim(),
      'email': emCtrl.text.trim(),
    };
    if (pwCtrl.text.isNotEmpty) body['password'] = pwCtrl.text;

    setState(() => _toggling.add(uid));
    try {
      final uri = _uriConToken('/api/gestion-usuarios/$uid/');
      final response = await http.patch(
        uri,
        headers: _buildHeaders(),
        body: json.encode(body),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        for (final lista in [_usuarios, _filtrados]) {
          final idx = lista.indexWhere((u) => (u['id'] as int?) == uid);
          if (idx != -1) {
            body.forEach((k, v) => lista[idx][k] = v);
            final first = (lista[idx]['first_name'] as String? ?? '').trim();
            final last = (lista[idx]['last_name'] as String? ?? '').trim();
            lista[idx]['_nombre'] = '$first $last'.trim();
          }
        }
        await _guardarCache(_usuarios);
        if (mounted) setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Usuario actualizado.'),

              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error ${response.statusCode}.'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(uid));
    }
  }

  Future<void> _eliminarUsuario(int userId, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_rounded, color: Colors.red.shade600, size: 22),
            const SizedBox(width: 10),
            const Text('Eliminar usuario', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          '¿Eliminar permanentemente al usuario "$nombre"?\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _toggling.add(userId));
    try {
      final uri = _uriConToken('/api/gestion-usuarios/$userId/');
      final response = await http.delete(uri, headers: _buildHeaders());
      if (response.statusCode == 204 || response.statusCode == 200) {
        _usuarios.removeWhere((u) => (u['id'] as int?) == userId);
        _filtrados.removeWhere((u) => (u['id'] as int?) == userId);
        _permisosCache.remove(userId);
        _activosCache.remove(userId);
        await _guardarCache(_usuarios);
        if (mounted) setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Usuario "$nombre" eliminado.'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error ${response.statusCode}: no se pudo eliminar.',
              ),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de red: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(userId));
    }
  }

  // ── Filtro ───────────────────────────────────────────────────────────────────

  void _filtrar() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtrados = _usuarios.where((u) {
        // Filtro por texto
        if (q.isNotEmpty) {
          final username = (u['username'] as String? ?? '').toLowerCase();
          final nombre = (u['_nombre'] as String? ?? '').toLowerCase();
          final email = (u['email'] as String? ?? '').toLowerCase();
          if (!username.contains(q) &&
              !nombre.contains(q) &&
              !email.contains(q)) {
            return false;
          }
        }
        // Filtro por tipo
        final uid = (u['id'] as int?) ?? 0;
        final isActivo =
            _activosCache[uid] ?? (u['is_active'] as bool? ?? true);
        final isSuperuser =
            u['is_superuser'] == true || u['is_superuser'] == 'true';
        switch (_filtroTipo) {
          case 'habilitados':
            return isActivo;
          case 'deshabilitados':
            return !isActivo;
          case 'admins':
            return isSuperuser;
          default:
            return true;
        }
      }).toList();
    });
  }

  Future<void> _guardarPermiso(int userId, String key, bool value) async {
    final permisos =
        _permisosCache[userId] ?? PermissionsService.defaultPermisos();
    permisos[key] = value;
    _permisosCache[userId] = permisos;

    // Usar los mismos headers/URI que el resto de llamadas del screen
    // (incluye Cookie de sesión) en lugar de PermissionsService que no la lleva.
    try {
      final uri = _uriConToken('/api/permisos-usuario/$userId/');
      final response = await http
          .patch(uri, headers: _buildHeaders(), body: json.encode(permisos))
          .timeout(const Duration(seconds: 8));
      debugPrint(
        '[Permisos] PATCH $userId status=${response.statusCode} body=${response.body}',
      );
      if (response.statusCode != 200 && response.statusCode != 204) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error al guardar permiso (${response.statusCode}): ${response.body.length > 120 ? response.body.substring(0, 120) : response.body}',
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Permisos] Error PATCH permiso: $e');
    }

    // Actualizar caché local independientemente
    await PermissionsService.guardarCacheLocal(userId, permisos);
    if (mounted) setState(() {});
  }

  Future<void> _guardarPermisosMasivo(
    int userId,
    Map<String, bool> permisos,
  ) async {
    _permisosCache[userId] = permisos;
    try {
      final uri = _uriConToken('/api/permisos-usuario/$userId/');
      final response = await http
          .patch(uri, headers: _buildHeaders(), body: json.encode(permisos))
          .timeout(const Duration(seconds: 8));
      debugPrint(
        '[Permisos] PATCH masivo $userId status=${response.statusCode}',
      );
    } catch (e) {
      debugPrint('[Permisos] Error PATCH masivo: $e');
    }
    await PermissionsService.guardarCacheLocal(userId, permisos);
    if (mounted) setState(() {});
  }

  void _mostrarPermisos(Map<String, dynamic> usuario) {
    final uid = (usuario['id'] as int?) ?? 0;
    final nombre = (usuario['_nombre'] as String?)?.isNotEmpty == true
        ? usuario['_nombre'] as String
        : usuario['username'] as String? ?? 'Usuario';
    final isSuperuser =
        usuario['is_superuser'] == true || usuario['is_superuser'] == 'true';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final permisos =
              _permisosCache[uid] ?? PermissionsService.defaultPermisos();

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.92,
            minChildSize: 0.5,
            builder: (_, scrollCtrl) {
              final isActivo = _activosCache[uid] ?? true;
              final isToggling = _toggling.contains(uid);
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            child: Text(
                              nombre.isNotEmpty ? nombre[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '@${usuario['username'] ?? ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSuperuser)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.amber.shade300,
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _editarUsuario(usuario);
                            },
                            child: const Tooltip(
                              message: 'Editar',
                              child: Icon(
                                Icons.edit_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _eliminarUsuario(uid, nombre);
                            },
                            child: Tooltip(
                              message: 'Eliminar',
                              child: Icon(
                                Icons.delete_rounded,
                                color: Colors.red.shade300,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Lista de permisos
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          if (isSuperuser) ...[
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.shield_rounded,
                                      size: 52,
                                      color: Colors.amber.shade400,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Administrador con acceso completo a todas las funciones.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _colorSubtexto,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          // ── Control habilitado/deshabilitado ──────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isActivo
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActivo
                                    ? Colors.green.shade200
                                    : Colors.red.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isActivo
                                      ? Icons.check_circle_rounded
                                      : Icons.block_rounded,
                                  color: isActivo
                                      ? Colors.green.shade600
                                      : Colors.red.shade600,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isActivo
                                            ? 'Cuenta habilitada'
                                            : 'Cuenta deshabilitada',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: isActivo
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                      Text(
                                        isActivo
                                            ? 'El usuario puede iniciar sesión.'
                                            : 'El usuario no puede iniciar sesión.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                isToggling
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _colorSecundario,
                                        ),
                                      )
                                    : Switch(
                                        value: isActivo,
                                        onChanged: (_) async {
                                          Navigator.pop(context);
                                          await _toggleActivo(
                                            uid,
                                            nombre,
                                            isActivo,
                                          );
                                        },
                                        activeThumbColor: Colors.green.shade600,
                                        inactiveThumbColor: Colors.red.shade400,
                                        inactiveTrackColor: Colors.red.shade100,
                                      ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // ── Control tipo de usuario ───────────────
                          Builder(
                            builder: (_) {
                              final esAdmin = isSuperuser;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F4FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF001F54,
                                    ).withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.manage_accounts_rounded,
                                          size: 16,
                                          color: Color(0xFF001F54),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Tipo de usuario',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Color(0xFF001F54),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _rolChip(
                                          label: 'Normal',
                                          icon: Icons.person_rounded,
                                          color: Colors.blueGrey,
                                          selected: !esAdmin,
                                          onTap: !esAdmin
                                              ? null
                                              : () {
                                                  Navigator.pop(context);
                                                  _cambiarTipoUsuario(
                                                    uid,
                                                    nombre,
                                                    false,
                                                  );
                                                },
                                        ),
                                        const SizedBox(width: 8),
                                        _rolChip(
                                          label: 'Superadmin',
                                          icon: Icons.shield_rounded,
                                          color: Colors.amber.shade700,
                                          selected: esAdmin,
                                          onTap: esAdmin
                                              ? null
                                              : () {
                                                  Navigator.pop(context);
                                                  _cambiarTipoUsuario(
                                                    uid,
                                                    nombre,
                                                    true,
                                                  );
                                                },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (!isSuperuser) ...[
                            const SizedBox(height: 16),
                            // Botones: otorgar / revocar todo
                            Row(
                              children: [
                                Expanded(
                                  child: _accionBoton(
                                    'Permitir todo',
                                    Icons.check_circle_rounded,
                                    Colors.green.shade700,
                                    () async {
                                      final todos =
                                          PermissionsService.defaultPermisos();
                                      _permisosCache[uid] = todos;
                                      await _guardarPermisosMasivo(uid, todos);
                                      if (ctx.mounted) setModalState(() {});
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _accionBoton(
                                    'Revocar todo',
                                    Icons.cancel_rounded,
                                    Colors.red.shade600,
                                    () async {
                                      final ninguno = {
                                        for (final k in PermisoKey.todos)
                                          k: false,
                                      };
                                      _permisosCache[uid] = ninguno;
                                      await _guardarPermisosMasivo(
                                        uid,
                                        ninguno,
                                      );
                                      if (ctx.mounted) setModalState(() {});
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            // Switches por permiso
                            ...PermisoKey.todos.map((key) {
                              final activo = permisos[key] ?? true;
                              return _permisoTile(
                                key: key,
                                activo: activo,
                                onChanged: (val) async {
                                  await _guardarPermiso(uid, key, val);
                                  if (ctx.mounted) setModalState(() {});
                                },
                              );
                            }),
                          ], // fin if (!isSuperuser)
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _permisoTile({
    required String key,
    required bool activo,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: activo
            ? const Color(0xFF5E17EB).withValues(alpha: 0.06)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: activo
                      ? const Color(0xFF5E17EB).withValues(alpha: 0.12)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconForKey(key),
                  color: activo
                      ? const Color(0xFF5E17EB)
                      : Colors.grey.shade400,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PermisoKey.etiqueta(key),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: activo
                            ? const Color(0xFF001F54)
                            : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PermisoKey.descripcion(key),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: activo,
                onChanged: onChanged,
                activeThumbColor: const Color(0xFF5E17EB),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForKey(String key) {
    switch (key) {
      case PermisoKey.vehiculos:
        return Icons.directions_car_rounded;
      case PermisoKey.tarjetas:
        return Icons.credit_card_rounded;
      case PermisoKey.multas:
        return Icons.search_rounded;
      case PermisoKey.notificaciones:
        return Icons.receipt_long_rounded;
      case PermisoKey.misNotificaciones:
        return Icons.notifications_active_rounded;
      case PermisoKey.beneficiarios:
        return Icons.people_alt_rounded;
      case PermisoKey.beneficiariosEscritura:
        return Icons.edit_note_rounded;
      case PermisoKey.credencial:
        return Icons.badge_rounded;
      default:
        return Icons.toggle_on_rounded;
    }
  }

  Widget _accionBoton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _rolChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? color : Colors.grey.shade400,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? color : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorSecundario],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.manage_accounts_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'SIMERT',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _colorPrimario,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cargando usuarios...',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(_colorSecundario),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTab(String label, int count, Color color, String filtro) {
    final isSelected = _filtroTipo == filtro;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _filtroTipo = filtro);
          _filtrar();
        },
        child: Container(
          padding: const EdgeInsets.only(bottom: 10, top: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsuarioCard(Map<String, dynamic> usuario) {
    final uid = (usuario['id'] as int?) ?? 0;
    final nombre = (usuario['_nombre'] as String?)?.isNotEmpty == true
        ? usuario['_nombre'] as String
        : usuario['username'] as String? ?? 'Usuario';
    final username = usuario['username'] as String? ?? '';
    final email = usuario['email'] as String? ?? '';
    final isSuperuser =
        usuario['is_superuser'] == true || usuario['is_superuser'] == 'true';
    final permisos = _permisosCache[uid];
    final isActivo = _activosCache[uid] ?? true;
    final isToggling = _toggling.contains(uid);

    // Contar permisos activos
    int activos = 0;
    int total = PermisoKey.todos.length;
    if (permisos != null) {
      activos = permisos.values.where((v) => v).length;
    } else {
      activos = total;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActivo ? Colors.grey.shade200 : Colors.red.shade200,
          width: isActivo ? 1 : 1.5,
        ),
      ),
      color: isActivo ? Colors.white : Colors.red.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _mostrarPermisos(usuario),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isActivo
                        ? (isSuperuser
                              ? Colors.amber.shade100
                              : const Color(0xFF5E17EB).withValues(alpha: 0.12))
                        : Colors.grey.shade200,
                    child: Text(
                      nombre.isNotEmpty ? nombre[0].toUpperCase() : 'U',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isActivo
                            ? (isSuperuser
                                  ? Colors.amber.shade700
                                  : const Color(0xFF5E17EB))
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                  if (!isActivo)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.block_rounded,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Datos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nombre,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isActivo
                                  ? const Color(0xFF001F54)
                                  : Colors.grey.shade500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSuperuser)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.amber.shade300,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'Admin',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@$username',
                      style: TextStyle(
                        fontSize: 12,
                        color: isActivo ? _colorSubtexto : Colors.grey.shade400,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Badge estado activo
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isActivo
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActivo
                                  ? Colors.green.shade300
                                  : Colors.red.shade300,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isActivo ? 'Habilitado' : 'Deshabilitado',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isActivo
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Barra de permisos
                        if (!isSuperuser)
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: total > 0 ? activos / total : 1,
                                      backgroundColor: Colors.grey.shade200,
                                      color: activos == total
                                          ? Colors.green.shade600
                                          : activos == 0
                                          ? Colors.red.shade400
                                          : const Color(0xFF5E17EB),
                                      minHeight: 5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$activos/$total',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Botón habilitar/deshabilitar
              Column(
                children: [
                  isToggling
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _colorSecundario,
                          ),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleActivo(uid, nombre, isActivo),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isActivo
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isActivo
                                    ? Colors.red.shade200
                                    : Colors.green.shade200,
                              ),
                            ),
                            child: Icon(
                              isActivo
                                  ? Icons.block_rounded
                                  : Icons.check_circle_rounded,
                              size: 18,
                              color: isActivo
                                  ? Colors.red.shade600
                                  : Colors.green.shade600,
                            ),
                          ),
                        ),
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Administración de Accesos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_colorPrimario, _colorSecundario],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: _fetchUsuarios,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Buscador ──────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorSecundario],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar usuario…',
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white60,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Colors.white60,
                        ),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── Tabs de filtro ─────────────────────────────────────────
          Container(
            color: Colors.white,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${_filtrados.length}/${_usuarios.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildStatTab(
                      'Todos',
                      _usuarios.length,
                      _colorPrimario,
                      'todos',
                    ),
                    _buildStatTab(
                      'Activos',
                      _usuarios.where((u) {
                        final uid = (u['id'] as int?) ?? 0;
                        return _activosCache[uid] ??
                            (u['is_active'] as bool? ?? true);
                      }).length,
                      Colors.green.shade700,
                      'habilitados',
                    ),
                    _buildStatTab(
                      'Inactivos',
                      _usuarios.where((u) {
                        final uid = (u['id'] as int?) ?? 0;
                        return !(_activosCache[uid] ??
                            (u['is_active'] as bool? ?? true));
                      }).length,
                      Colors.red.shade600,
                      'deshabilitados',
                    ),
                    _buildStatTab(
                      'Admins',
                      _usuarios
                          .where(
                            (u) =>
                                u['is_superuser'] == true ||
                                u['is_superuser'] == 'true',
                          )
                          .length,
                      Colors.amber.shade700,
                      'admins',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Lista ─────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? _buildCargando()
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 56,
                            color: Color(0xFFB0B0B0),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _colorSubtexto,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _fetchUsuarios,
                            icon: const Icon(Icons.refresh_rounded),
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
                  )
                : _filtrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_off_outlined,
                          size: 48,
                          color: Color(0xFFB0B0B0),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchCtrl.text.isEmpty
                              ? 'No se encontraron usuarios.\n(token: ${_token?.isNotEmpty == true ? "presente" : "AUSENTE"})'
                              : 'Sin resultados para "${_searchCtrl.text}"',
                          style: const TextStyle(color: _colorSubtexto),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: _colorSecundario,
                    onRefresh: _fetchUsuarios,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      itemCount: _filtrados.length,
                      itemBuilder: (_, i) => _buildUsuarioCard(_filtrados[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _crearUsuario,
        backgroundColor: _colorSecundario,
        tooltip: 'Nuevo usuario',
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
      ),
    );
  }
}

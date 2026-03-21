import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Claves de permisos disponibles en la aplicación.
class PermisoKey {
  static const String vehiculos = 'perm_vehiculos';
  static const String tarjetas = 'perm_tarjetas';
  static const String multas = 'perm_multas';
  static const String notificaciones = 'perm_notificaciones';
  static const String misNotificaciones = 'perm_mis_notificaciones';
  static const String beneficiarios = 'perm_beneficiarios';
  static const String beneficiariosEscritura = 'perm_beneficiarios_escritura';
  static const String credencial = 'perm_credencial';

  static const List<String> todos = [
    vehiculos,
    tarjetas,
    multas,
    notificaciones,
    misNotificaciones,
    beneficiarios,
    beneficiariosEscritura,
    credencial,
  ];

  static String etiqueta(String key) {
    switch (key) {
      case vehiculos:
        return 'Datos de Vehículos';
      case tarjetas:
        return 'Control de Tarjetas';
      case multas:
        return 'Consultar Multas';
      case notificaciones:
        return 'Notificaciones';
      case misNotificaciones:
        return 'Mis Notificaciones';
      case beneficiarios:
        return 'Beneficio Adult. Mayor / Discap.';
      case beneficiariosEscritura:
        return 'Registro / Edición Beneficiarios';
      case credencial:
        return 'Credencial';
      default:
        return key;
    }
  }

  static String descripcion(String key) {
    switch (key) {
      case vehiculos:
        return 'Consultar datos de vehículos por placa';
      case tarjetas:
        return 'Registrar y ver tarjetas de estacionamiento';
      case multas:
        return 'Consultar y ver multas / infracciones';
      case notificaciones:
        return 'Ver notificaciones del sistema';
      case misNotificaciones:
        return 'Ver notificaciones propias del usuario';
      case beneficiarios:
        return 'Consultar adultos mayores y discapacitados';
      case beneficiariosEscritura:
        return 'Registrar y modificar beneficiarios';
      case credencial:
        return 'Ver credencial digital del usuario';
      default:
        return '';
    }
  }
}

/// Servicio de permisos.
/// Fuente principal: API  GET/PATCH /api/permisos-usuario/{userId}/
/// Caché local:      SharedPreferences  con clave permisos_usuario_{userId}
///
/// El superusuario siempre tiene todos los permisos.
/// Los usuarios nuevos/sin configuración tienen todos los permisos por defecto.
class PermissionsService {
  static const String _prefixKey = 'permisos_usuario_';
  static const String _baseUrl = 'https://simert.transitoelguabo.gob.ec';

  static Map<String, bool> defaultPermisos() {
    return {for (final k in PermisoKey.todos) k: true};
  }

  // ── Helpers internos ──────────────────────────────────────────────────────

  static Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Uri _uri(String path, String? token) {
    final base = '$_baseUrl$path';
    if (token != null && token.isNotEmpty) {
      return Uri.parse(base).replace(queryParameters: {'_tk': token.trim()});
    }
    return Uri.parse(base);
  }

  static Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty)
      'Authorization': 'Token ${token.trim()}',
  };

  // ── Caché local ───────────────────────────────────────────────────────────

  static Future<void> _guardarCache(
    int userId,
    Map<String, bool> permisos,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixKey$userId', json.encode(permisos));
  }

  /// Versión pública para que otras clases puedan actualizar solo la caché
  /// local sin disparar el PATCH a la API.
  static Future<void> guardarCacheLocal(
    int userId,
    Map<String, bool> permisos,
  ) => _guardarCache(userId, permisos);

  static Future<Map<String, bool>?> _leerCache(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixKey$userId');
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final result = defaultPermisos();
      for (final key in PermisoKey.todos) {
        if (decoded.containsKey(key)) {
          result[key] = decoded[key] as bool? ?? true;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  // ── API ───────────────────────────────────────────────────────────────────

  static Future<Map<String, bool>?> _fetchDeApi(int userId) async {
    try {
      final token = await _token();
      final uri = _uri('/api/permisos-usuario/$userId/', token);
      final response = await http
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final result = defaultPermisos();
        for (final key in PermisoKey.todos) {
          if (decoded.containsKey(key)) {
            result[key] = decoded[key] as bool? ?? true;
          }
        }
        return result;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _patchEnApi(
    int userId,
    Map<String, bool> permisos,
  ) async {
    try {
      final token = await _token();
      final uri = _uri('/api/permisos-usuario/$userId/', token);
      final response = await http
          .patch(uri, headers: _headers(token), body: json.encode(permisos))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // ── API pública ───────────────────────────────────────────────────────────

  /// Obtiene permisos: caché → default (inmediato), API en background para próxima vez.
  static Future<Map<String, bool>> getPermisos(int userId) async {
    // 1. Caché local primero (instantáneo, sin red)
    final cache = await _leerCache(userId);
    if (cache != null) {
      // Refrescar desde API en background para la próxima vez
      _fetchDeApi(userId)
          .then((apiResult) {
            if (apiResult != null) _guardarCache(userId, apiResult);
          })
          .catchError((_) {});
      return cache;
    }
    // 2. Sin caché → intentar API
    final apiResult = await _fetchDeApi(userId);
    if (apiResult != null) {
      await _guardarCache(userId, apiResult);
      return apiResult;
    }
    // 3. Fallback: permisos por defecto
    return defaultPermisos();
  }

  /// Guarda permisos: primero en la API, luego en caché local.
  static Future<void> setPermisos(
    int userId,
    Map<String, bool> permisos,
  ) async {
    await _patchEnApi(userId, permisos); // best-effort
    await _guardarCache(userId, permisos); // siempre guarda localmente
  }

  /// Verifica un permiso puntual. Superusuarios siempre tienen permiso.
  static Future<bool> tienePermiso(
    int userId,
    String key, {
    bool isSuperuser = false,
  }) async {
    if (isSuperuser) return true;
    final permisos = await getPermisos(userId);
    return permisos[key] ?? true;
  }
}

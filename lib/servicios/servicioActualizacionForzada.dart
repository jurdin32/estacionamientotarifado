import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resultado de la verificación de versión.
class ResultadoVerificacion {
  final bool hayActualizacion;
  final bool esForzada;
  final String versionDisponible;
  final int buildDisponible;
  final String urlPlayStore;
  final String? mensaje;

  ResultadoVerificacion({
    required this.hayActualizacion,
    required this.esForzada,
    required this.versionDisponible,
    required this.buildDisponible,
    required this.urlPlayStore,
    this.mensaje,
  });
}

/// Servicio que verifica si hay una versión más reciente de la app
/// y si la actualización es obligatoria.
class ServicioActualizacionForzada {
  static const String _urlVersion =
      'https://simert.transitoelguabo.gob.ec/api/version-app/';
  static const String _cacheKey = 'ultima_version_check';
  static const Duration _cacheDuracion = Duration(hours: 6);

  /// Verifica si hay una actualización disponible consultando el servidor.
  /// Usa caché local de 6 horas para no saturar el servidor.
  static Future<ResultadoVerificacion?> verificar({
    bool forceRefresh = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Usar caché si no se fuerza refresco
      if (!forceRefresh) {
        final cache = prefs.getString(_cacheKey);
        if (cache != null) {
          try {
            final decoded = json.decode(cache) as Map<String, dynamic>;
            final timestamp = decoded['timestamp'] as int? ?? 0;
            final ahora = DateTime.now().millisecondsSinceEpoch;
            if (ahora - timestamp < _cacheDuracion.inMilliseconds) {
              // Caché válido, devolver resultado
              return ResultadoVerificacion(
                hayActualizacion:
                    decoded['hay_actualizacion'] as bool? ?? false,
                esForzada: decoded['es_forzada'] as bool? ?? false,
                versionDisponible: decoded['version'] as String? ?? '',
                buildDisponible: decoded['build'] as int? ?? 0,
                urlPlayStore: decoded['url'] as String? ?? '',
                mensaje: decoded['mensaje'] as String?,
              );
            }
          } catch (_) {
            // Caché corrupto, ignorar
          }
        }
      }

      // Consultar servidor
      final response = await HttpMonitorizado.get(
        Uri.parse(_urlVersion),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final versionServidor = data['version'] as String? ?? '';
      final buildServidor = data['build'] as int? ?? 0;
      final esForzada = data['force_update'] as bool? ?? false;
      final url = data['url'] as String? ?? '';
      final mensaje = data['mensaje'] as String?;

      // Obtener versión local
      final info = await PackageInfo.fromPlatform();
      final buildLocal = int.tryParse(info.buildNumber) ?? 0;

      final hayActualizacion = buildServidor > buildLocal;

      // Guardar en caché
      if (hayActualizacion || forceRefresh) {
        final cacheData = {
          'hay_actualizacion': hayActualizacion,
          'es_forzada': esForzada,
          'version': versionServidor,
          'build': buildServidor,
          'url': url,
          'mensaje': mensaje,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        await prefs.setString(_cacheKey, json.encode(cacheData));
      }

      return ResultadoVerificacion(
        hayActualizacion: hayActualizacion,
        esForzada: esForzada,
        versionDisponible: versionServidor,
        buildDisponible: buildServidor,
        urlPlayStore: url,
        mensaje: mensaje,
      );
    } catch (e) {
      // Si falla la conexión, no bloquear al usuario
      debugPrint('⚠️ Error verificando actualización: $e');
      return null;
    }
  }
}

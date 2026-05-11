import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio que permite minimizar la aplicación y enviar el token de sesión
/// al servicio foreground nativo (ServicioPersistente.kt) para que pueda
/// consultar la API independientemente aunque la app Flutter esté cerrada.
class ServicioMinimizar {
  static const _channel = MethodChannel('com.simert.estacionamiento/minimizar');

  /// Minimiza la aplicación llevándola a segundo plano.
  static void minimizar() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _channel.invokeMethod('minimizar');
    } catch (_) {}
  }

  /// Envía el token de sesión al servicio nativo para que pueda
  /// consultar la API aunque la app Flutter esté cerrada.
  /// Debe llamarse después del login y cada vez que se renueve el token.
  static Future<void> enviarTokenAlServicioNatvio() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final name = prefs.getString('name') ?? '';
      final id = prefs.getInt('id') ?? 0;
      if (token.isEmpty) return;
      await _channel.invokeMethod('enviarToken', {
        'token': token,
        'nombre_usuario': name,
        'id_usuario': id,
      });
    } catch (_) {}
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../tarjetas/models/Tarjetas.dart';

/// Servicio que actualiza las SharedPreferences con los datos más recientes
/// para que el Servicio Android nativo (ServicioPersistente.kt) pueda
/// mostrar la notificación persistente con cuenta regresiva.
///
/// La notificación persistente REAL la maneja el Servicio Android nativo
/// (ServicioPersistente.kt), que NO se cierra cuando la app Flutter se cierra.
///
/// Este servicio solo se encarga de:
/// 1. Escribir en SharedPreferences los datos que Flutter recibe vía WebSocket
/// 2. Liberar localmente los estacionamientos expirados
/// 3. NO muestra ninguna notificación (eso lo hace el servicio nativo)
class ServicioNotificacionesBackground {
  static Timer? _timerLiberacion;
  static bool _inicializado = false;

  /// Inicializa el timer de liberación de expirados.
  /// NO muestra notificaciones — eso lo hace el servicio Android nativo.
  static Future<void> iniciarServicio() async {
    if (_inicializado) {
      debugPrint('🟢 Servicio ya inicializado');
      return;
    }
    _inicializado = true;
    debugPrint('🟢 Iniciando servicio de liberación local (sin notificación)');

    // Liberar expirados cada 30 segundos
    _timerLiberacion?.cancel();
    _timerLiberacion = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _liberarExpiradosLocalmente();
      } catch (e) {
        debugPrint('⚠️ Error en timer liberación: $e');
      }
    });

    // Ejecutar inmediatamente
    await _liberarExpiradosLocalmente();
  }

  /// Detiene los timers
  static void detenerServicio() {
    _timerLiberacion?.cancel();
    _timerLiberacion = null;
    _inicializado = false;
    debugPrint('🛑 Servicio detenido');
  }

  /// Fuerza una liberación inmediata de expirados
  static Future<void> actualizarAhora() async {
    try {
      await _liberarExpiradosLocalmente();
    } catch (e) {
      debugPrint('⚠️ Error en actualizarAhora: $e');
    }
  }

  /// Ejecuta la tarea de background (llamado por WorkManager incluso con app cerrada).
  /// Solo libera expirados localmente desde SharedPreferences, SIN llamar a la API.
  static Future<void> ejecutarTareaBackground() async {
    debugPrint('🔄 [Background] Ejecutando tarea programada');
    await _liberarExpiradosLocalmente();
    debugPrint('✅ [Background] Tarea completada');
  }

  /// Libera localmente los estacionamientos cuyo tiempo haya expirado.
  /// Solo opera sobre SharedPreferences, SIN llamar a la API.
  static Future<void> _liberarExpiradosLocalmente() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final jsonString = prefs.getString('estacionamientos_tarjeta');
      if (jsonString == null || jsonString.isEmpty) return;

      final List<dynamic> jsonData = json.decode(jsonString);
      final List<Estacionamiento_Tarjeta> tarjetas = jsonData
          .map(
            (item) =>
                Estacionamiento_Tarjeta.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      if (tarjetas.isEmpty) return;

      final ahora = DateTime.now();
      final List<int> idsLiberados = [];

      for (final t in tarjetas) {
        if (t.estacionId <= 0) continue;
        try {
          final hEntrada = DateFormat('HH:mm').parse(t.horaEntrada);
          final hSalida = DateFormat('HH:mm').parse(t.horaSalida);
          final entrada = DateTime(
            ahora.year,
            ahora.month,
            ahora.day,
            hEntrada.hour,
            hEntrada.minute,
          );
          final salida = DateTime(
            ahora.year,
            ahora.month,
            ahora.day,
            hSalida.hour,
            hSalida.minute,
          );

          DateTime salidaReal = salida;
          if (salida.isBefore(entrada)) {
            salidaReal = salida.add(const Duration(days: 1));
          }

          if (!salidaReal.isAfter(ahora)) {
            idsLiberados.add(t.estacionId);
          }
        } catch (_) {}
      }

      if (idsLiberados.isEmpty) return;

      debugPrint(
        '🧹 Liberando ${idsLiberados.length} estacionamientos expirados',
      );

      // Eliminar del caché de tarjetas
      final actualizadas = tarjetas
          .where((t) => !idsLiberados.contains(t.estacionId))
          .toList();
      await prefs.setString(
        'estacionamientos_tarjeta',
        json.encode(actualizadas.map((t) => t.toJson()).toList()),
      );

      // Actualizar caché de estacionamientos
      final estacionesJson = prefs.getString('estacionamientos');
      if (estacionesJson != null) {
        final List<dynamic> estacionesData = json.decode(estacionesJson);
        bool huboCambio = false;
        for (final est in estacionesData) {
          if (idsLiberados.contains(est['id']) && est['estado'] == true) {
            est['estado'] = false;
            est['placa'] = '';
            huboCambio = true;
          }
        }
        if (huboCambio) {
          await prefs.setString(
            'estacionamientos',
            json.encode(estacionesData),
          );
        }
      }

      debugPrint('✅ ${idsLiberados.length} liberados localmente');
    } catch (e) {
      debugPrint('❌ Error liberando expirados: $e');
    }
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registra el consumo de datos (bytes enviados/recibidos) de la app.
///
/// Uso:
/// ```dart
/// MonitorDatos.instancia.registrarRequest(bytesEnviados, bytesRecibidos, endpoint);
/// ```
class MonitorDatos {
  MonitorDatos._();
  static final MonitorDatos instancia = MonitorDatos._();

  // ── Contadores en memoria ─────────────────────────────────────────────────
  int _bytesEnviadosSesion = 0;
  int _bytesRecibidosSesion = 0;
  int _requestsSesion = 0;
  int _wsMessagesSesion = 0;
  int _wsBytesRecibidosSesion = 0;

  // Contadores persistentes (acumulados)
  int _bytesEnviadosTotal = 0;
  int _bytesRecibidosTotal = 0;
  int _requestsTotal = 0;

  // Historial por endpoint (últimos registros)
  final List<RegistroDatos> _historial = [];
  static const int _maxHistorial = 100;

  // Stream para notificar cambios a la UI
  final StreamController<void> _cambioController =
      StreamController<void>.broadcast();

  /// Stream que emite cada vez que hay un cambio en los contadores.
  Stream<void> get onCambio => _cambioController.stream;

  // ── Getters ───────────────────────────────────────────────────────────────

  int get bytesEnviadosSesion => _bytesEnviadosSesion;
  int get bytesRecibidosSesion => _bytesRecibidosSesion;
  int get totalBytesSesion => _bytesEnviadosSesion + _bytesRecibidosSesion;
  int get requestsSesion => _requestsSesion;
  int get wsMessagesSesion => _wsMessagesSesion;
  int get wsBytesRecibidosSesion => _wsBytesRecibidosSesion;

  int get bytesEnviadosTotal => _bytesEnviadosTotal;
  int get bytesRecibidosTotal => _bytesRecibidosTotal;
  int get totalBytesTotal => _bytesEnviadosTotal + _bytesRecibidosTotal;
  int get requestsTotal => _requestsTotal;

  List<RegistroDatos> get historial => List.unmodifiable(_historial);

  // ── API pública ───────────────────────────────────────────────────────────

  /// Inicializar: cargar datos persistidos.
  Future<void> inicializar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bytesEnviadosTotal = prefs.getInt('monitor_bytes_env') ?? 0;
      _bytesRecibidosTotal = prefs.getInt('monitor_bytes_rec') ?? 0;
      _requestsTotal = prefs.getInt('monitor_requests') ?? 0;
    } catch (e) {
      debugPrint('[Monitor] Error al inicializar: $e');
    }
  }

  /// Registrar una request HTTP.
  void registrarRequest(
    int bytesEnviados,
    int bytesRecibidos,
    String endpoint, {
    String metodo = 'GET',
    int statusCode = 200,
  }) {
    _bytesEnviadosSesion += bytesEnviados;
    _bytesRecibidosSesion += bytesRecibidos;
    _requestsSesion++;

    _bytesEnviadosTotal += bytesEnviados;
    _bytesRecibidosTotal += bytesRecibidos;
    _requestsTotal++;

    _historial.insert(
      0,
      RegistroDatos(
        timestamp: DateTime.now(),
        endpoint: endpoint,
        metodo: metodo,
        bytesEnviados: bytesEnviados,
        bytesRecibidos: bytesRecibidos,
        tipo: TipoDato.http,
        statusCode: statusCode,
      ),
    );
    if (_historial.length > _maxHistorial) {
      _historial.removeRange(_maxHistorial, _historial.length);
    }

    _notificar();
    _persistirDebounced();
  }

  /// Registrar un mensaje WebSocket recibido.
  void registrarWsRecibido(int bytes, String canal) {
    _wsBytesRecibidosSesion += bytes;
    _wsMessagesSesion++;
    _bytesRecibidosSesion += bytes;
    _bytesRecibidosTotal += bytes;

    _historial.insert(
      0,
      RegistroDatos(
        timestamp: DateTime.now(),
        endpoint: 'ws/$canal',
        metodo: 'WS',
        bytesEnviados: 0,
        bytesRecibidos: bytes,
        tipo: TipoDato.websocket,
      ),
    );
    if (_historial.length > _maxHistorial) {
      _historial.removeRange(_maxHistorial, _historial.length);
    }

    _notificar();
    _persistirDebounced();
  }

  /// Registrar un mensaje WebSocket enviado.
  void registrarWsEnviado(int bytes) {
    _bytesEnviadosSesion += bytes;
    _bytesEnviadosTotal += bytes;
    _notificar();
  }

  /// Reiniciar contadores de sesión.
  void resetearSesion() {
    _bytesEnviadosSesion = 0;
    _bytesRecibidosSesion = 0;
    _requestsSesion = 0;
    _wsMessagesSesion = 0;
    _wsBytesRecibidosSesion = 0;
    _historial.clear();
    _notificar();
  }

  /// Reiniciar todos los contadores (sesión + acumulados).
  Future<void> resetearTodo() async {
    resetearSesion();
    _bytesEnviadosTotal = 0;
    _bytesRecibidosTotal = 0;
    _requestsTotal = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('monitor_bytes_env');
    await prefs.remove('monitor_bytes_rec');
    await prefs.remove('monitor_requests');
    _notificar();
  }

  // ── Internos ──────────────────────────────────────────────────────────────

  Timer? _notificarTimer;
  void _notificar() {
    // Throttle: máximo una notificación cada 2 segundos para evitar
    // reconstrucciones excesivas de UI en la pantalla de monitor.
    if (_notificarTimer?.isActive ?? false) return;
    _notificarTimer = Timer(const Duration(seconds: 2), () {
      if (!_cambioController.isClosed) {
        _cambioController.add(null);
      }
    });
  }

  Timer? _persistTimer;
  void _persistirDebounced() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 5), _persistir);
  }

  Future<void> _persistir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('monitor_bytes_env', _bytesEnviadosTotal);
      await prefs.setInt('monitor_bytes_rec', _bytesRecibidosTotal);
      await prefs.setInt('monitor_requests', _requestsTotal);
    } catch (e) {
      debugPrint('[Monitor] Error al persistir: $e');
    }
  }

  // ── Utilidades de formato ─────────────────────────────────────────────────

  /// Convierte bytes a formato legible (KB, MB, GB).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

enum TipoDato { http, websocket }

class RegistroDatos {
  final DateTime timestamp;
  final String endpoint;
  final String metodo;
  final int bytesEnviados;
  final int bytesRecibidos;
  final TipoDato tipo;
  final int statusCode;

  const RegistroDatos({
    required this.timestamp,
    required this.endpoint,
    required this.metodo,
    required this.bytesEnviados,
    required this.bytesRecibidos,
    required this.tipo,
    this.statusCode = 0,
  });

  int get totalBytes => bytesEnviados + bytesRecibidos;
}

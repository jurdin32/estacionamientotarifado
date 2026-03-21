import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:estacionamientotarifado/servicios/monitorDatos.dart';

/// Evento genérico recibido desde el WebSocket.
///
/// [canal] identifica el tipo de datos (ej: 'estaciones', 'tarjetas',
/// 'notificaciones', 'multas', etc.).
/// [accion] es la operación: 'snapshot', 'create', 'update', 'delete'.
/// [datos] contiene el payload JSON decodificado.
class WsEvento {
  final String canal;
  final String accion;
  final dynamic datos;

  const WsEvento({
    required this.canal,
    required this.accion,
    required this.datos,
  });

  factory WsEvento.fromJson(Map<String, dynamic> json) => WsEvento(
    canal: json['canal'] as String? ?? '',
    accion: json['accion'] as String? ?? 'snapshot',
    datos: json['datos'],
  );
}

/// Servicio singleton que gestiona la conexión WebSocket con el backend.
///
/// Uso típico:
/// ```dart
/// final ws = ServicioWebSocket.instancia;
/// ws.conectar();
/// ws.escuchar('estaciones').listen((evento) { ... });
/// ```
class ServicioWebSocket {
  ServicioWebSocket._();
  static final ServicioWebSocket instancia = ServicioWebSocket._();

  // ── Configuración ─────────────────────────────────────────────────────────
  /// URL base del WebSocket. Se configura en [conectar] o aquí como default.
  static const String _wsBaseUrl =
      'wss://simert.transitoelguabo.gob.ec/ws/sync/';

  // ── Estado interno ────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  bool _conectado = false;
  bool _reconectando = false;
  bool _disposado = false;
  Timer? _heartbeatTimer;
  Timer? _reconexionTimer;
  StreamSubscription? _channelSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String _token = '';

  /// Canales a los que el cliente está suscrito.
  /// Se re-envían automáticamente al reconectar.
  final Set<String> _canalesSuscritos = {};

  int _intentosReconexion = 0;
  static const int _maxIntentosReconexion = 10;

  /// Stream controller broadcast para difundir los eventos a múltiples listeners.
  final StreamController<WsEvento> _eventController =
      StreamController<WsEvento>.broadcast();

  /// Stream que notifica cambios en el estado de conexión (true = conectado).
  final StreamController<bool> _estadoController =
      StreamController<bool>.broadcast();

  bool _enBackground = false;

  /// Indica si la app está en segundo plano.
  bool get enBackground => _enBackground;

  /// Indica si la conexión está activa.
  bool get conectado => _conectado;

  /// Stream reactivo del estado de conexión.
  Stream<bool> get onEstadoCambio => _estadoController.stream;

  // ── API Pública ───────────────────────────────────────────────────────────

  /// Inicia la conexión WebSocket.
  ///
  /// [token] se envía como query-param para autenticación.
  /// Si ya está conectado, no hace nada.
  Future<void> conectar({String? token}) async {
    if (_conectado || _reconectando) return;
    _disposado = false;

    if (token != null) {
      _token = token;
    } else {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token') ?? '';
    }

    _conectarInterno();
    _iniciarMonitorConectividad();
  }

  /// Desconecta y libera recursos. Llamar al hacer logout o dispose de la app.
  void desconectar() {
    _disposado = true;
    _cancelarTimers();
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _conectado = false;
    _intentosReconexion = 0;
    debugPrint('[WS] Desconectado manualmente');
  }

  /// Envía un mensaje JSON al servidor. Útil para suscribirse a canales
  /// específicos o enviar comandos.
  void enviar(Map<String, dynamic> mensaje) {
    if (!_conectado || _channel == null) {
      debugPrint('[WS] Intento de envío sin conexión activa');
      return;
    }
    final encoded = json.encode(mensaje);
    MonitorDatos.instancia.registrarWsEnviado(encoded.length);
    _channel!.sink.add(encoded);
  }

  /// Suscribirse a un canal específico (ej: 'estaciones', 'tarjetas').
  /// Solicita al servidor enviar datos de ese canal.
  void suscribir(String canal) {
    _canalesSuscritos.add(canal);
    if (_conectado) {
      enviar({'tipo': 'suscribir', 'canal': canal});
    }
  }

  /// Cancelar suscripción a un canal.
  void desuscribir(String canal) {
    _canalesSuscritos.remove(canal);
    if (_conectado) {
      enviar({'tipo': 'desuscribir', 'canal': canal});
    }
  }

  /// Stream filtrado por canal. Emite solo los eventos del canal indicado.
  Stream<WsEvento> escuchar(String canal) {
    return _eventController.stream.where((e) => e.canal == canal);
  }

  /// Stream de todos los eventos sin filtrar.
  Stream<WsEvento> get eventos => _eventController.stream;

  // ── Conexión interna ──────────────────────────────────────────────────────

  void _conectarInterno() {
    _reconectando = true;
    try {
      final uri = Uri.parse('$_wsBaseUrl?token=${Uri.encodeComponent(_token)}');
      _channel = WebSocketChannel.connect(uri);
      _channelSubscription?.cancel();
      _channelSubscription = _channel!.stream.listen(
        _onMensaje,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _conectado = true;
      _reconectando = false;
      _intentosReconexion = 0;
      _emitirEstado(true);
      _iniciarHeartbeat();
      // Re-suscribir a todos los canales registrados
      _resuscribirCanales();
      debugPrint('[WS] Conectado a $uri');
    } catch (e) {
      _conectado = false;
      _reconectando = false;
      debugPrint('[WS] Error al conectar: $e');
      _programarReconexion();
    }
  }

  void _onMensaje(dynamic mensaje) {
    try {
      final raw = mensaje as String;
      final Map<String, dynamic> data = json.decode(raw);

      // Registrar consumo WS
      MonitorDatos.instancia.registrarWsRecibido(
        raw.length,
        data['canal'] as String? ?? 'sistema',
      );

      // Respuestas de hearbeat
      if (data['tipo'] == 'pong') return;

      final evento = WsEvento.fromJson(data);
      if (!_eventController.isClosed) {
        _eventController.add(evento);
      }
    } catch (e) {
      debugPrint('[WS] Error parseando mensaje: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('[WS] Error en stream: $error');
    _conectado = false;
    _emitirEstado(false);
    if (!_disposado) _programarReconexion();
  }

  void _onDone() {
    debugPrint('[WS] Conexión cerrada');
    _conectado = false;
    _emitirEstado(false);
    if (!_disposado) _programarReconexion();
  }

  // ── Heartbeat ─────────────────────────────────────────────────────────────

  void _iniciarHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_conectado) {
        enviar({'tipo': 'ping'});
      }
    });
  }

  // ── Reconexión con back-off exponencial ───────────────────────────────────

  void _programarReconexion() {
    if (_disposado || _reconectando) return;
    if (_intentosReconexion >= _maxIntentosReconexion) {
      debugPrint('[WS] Máximo de reintentos alcanzado');
      return;
    }

    _intentosReconexion++;
    // Back-off: 2s, 4s, 8s, 16s, 32s, 60s (máx)
    final delay = Duration(seconds: (1 << _intentosReconexion).clamp(2, 60));
    debugPrint('[WS] Reconexión #$_intentosReconexion en ${delay.inSeconds}s');

    _reconexionTimer?.cancel();
    _reconexionTimer = Timer(delay, () {
      if (!_disposado && !_conectado) _conectarInterno();
    });
  }

  // ── Monitoreo de conectividad ─────────────────────────────────────────────

  void _iniciarMonitorConectividad() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final result = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      if (result != ConnectivityResult.none && !_conectado && !_disposado) {
        debugPrint('[WS] Red recuperada — reconectando');
        _intentosReconexion = 0;
        _conectarInterno();
      }
    });
  }

  // ── Utilidades ────────────────────────────────────────────────────────────

  void _emitirEstado(bool conectado) {
    if (!_estadoController.isClosed) {
      _estadoController.add(conectado);
    }
  }

  void _cancelarTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconexionTimer?.cancel();
    _reconexionTimer = null;
  }

  /// Reduce la actividad cuando la app va a background.
  /// Mantiene la conexión WS viva y sigue recibiendo datos,
  /// pero reduce el heartbeat para ahorrar batería.
  void pausar() {
    _enBackground = true;
    // Reducir heartbeat a cada 90s en background (ahorro de batería)
    _heartbeatTimer?.cancel();
    if (_conectado) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 90), (_) {
        if (_conectado) enviar({'tipo': 'ping'});
      });
    }
    debugPrint('[WS] Modo background — conexión viva, heartbeat reducido');
  }

  /// Restaura la actividad completa al volver a foreground.
  void reanudar() {
    _enBackground = false;
    if (_conectado) {
      // Restaurar heartbeat normal
      _iniciarHeartbeat();
      debugPrint('[WS] Modo foreground — heartbeat restaurado');
    } else if (!_disposado) {
      debugPrint('[WS] Reanudando conexión');
      _intentosReconexion = 0;
      _conectarInterno();
    }
  }

  /// Resetea completamente y fuerza una nueva conexión.
  void resetear() {
    desconectar();
    _disposado = false;
  }

  /// Re-envía suscripciones de canales tras reconectar.
  void _resuscribirCanales() {
    for (final canal in _canalesSuscritos) {
      enviar({'tipo': 'suscribir', 'canal': canal});
    }
    if (_canalesSuscritos.isNotEmpty) {
      debugPrint('[WS] Re-suscrito a: ${_canalesSuscritos.join(', ')}');
    }
  }
}

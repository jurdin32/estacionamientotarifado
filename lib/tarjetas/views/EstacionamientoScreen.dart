import 'dart:convert';
import 'dart:async';
import 'package:estacionamientotarifado/servicios/servicioEstacionamiento.dart';
import 'package:estacionamientotarifado/servicios/servicioEstacionamientoTarjeta.dart';
import 'package:estacionamientotarifado/servicios/servicioWebSocket.dart';
import 'package:estacionamientotarifado/tarjetas/models/Estacionamiento.dart';
import 'package:estacionamientotarifado/tarjetas/models/Tarjetas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../snnipers/cambia_mayusculas.dart';

class EstacionamientoScreen extends StatefulWidget {
  const EstacionamientoScreen({super.key});

  @override
  State<EstacionamientoScreen> createState() => _EstacionamientoScreenState();
}

class _EstacionamientoScreenState extends State<EstacionamientoScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List<Estacionamiento> _estaciones = [];
  List<Estacionamiento> _filteredEstaciones = [];
  List<Estacionamiento> _rangedEstaciones = [];
  List<Estacionamiento_Tarjeta> _estacionamientosTarjeta = [];

  /// Mapa {numero_tarjeta → minutos_consumidos} sincronizado desde /api/tarjeta/.
  /// Es la fuente de verdad para calcular el saldo disponible en cada tarjeta.
  Map<int, int> _tiemposTarjeta = {};

  /// Mapa {usuario_id → nombre} para mostrar quién registró cada estacionamiento.
  Map<int, String> _nombresUsuarios = {};

  bool _isLoading = true;
  String _searchQuery = '';
  String _rangoEstacionamientos = '';
  int? _usuario;
  final Color primaryColor = const Color(0xFF0A1628);
  final Color disabledColor = Colors.blue;
  final Color successColor = const Color(0xFF00C853);
  final Color errorColor = const Color(0xFFD32F2F);
  final Color warningColor = const Color(0xFFFF9800);

  final List<TextEditingController> _controllers = [];
  final Map<int, bool> _estacionamientosLiberando = {};

  /// IDs de estacionamientos cuya sincronización con el servidor está en curso.
  /// El polling ignora estos IDs para evitar sobreescribir cambios pendientes.
  final Set<int> _enProceso = {};
  Timer? _pollingTimer;
  bool _isRefreshing = false;

  /// Suscripción WebSocket para recibir actualizaciones en tiempo real.
  StreamSubscription<WsEvento>? _wsEstacionesSub;
  StreamSubscription<WsEvento>? _wsTarjetasSub;
  StreamSubscription<bool>? _wsEstadoSub;
  bool _wsConectado = false;

  /// Polling de fallback: activo solo cuando el WebSocket está caído.
  static const Duration _fallbackPollingInterval = Duration(seconds: 45);

  /// Debounce para persistir caché: evita escrituras excesivas a disco.
  Timer? _persistDebounce;

  /// Throttle para reintentos de conexión por cambio de red.
  DateTime _ultimoReintento = DateTime(2000);

  /// Debounce para evitar múltiples ciclos resumed en ráfaga.
  DateTime _ultimoResumed = DateTime(2000);

  /// Timer del fallback para evitar agendarlo múltiples veces.
  Timer? _fallbackPendiente;

  final TextEditingController _rangoController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _appEnSegundoPlano = false;
  String _filtroEstado = 'todos'; // 'todos' | 'ocupados' | 'disponibles'
  String _token = '';
  late TabController _tabController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // StreamSubscription para manejar las notificaciones de OneSignal
  StreamSubscription<OSNotification>? _notificationStreamSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _cambiarFiltroTab(_tabController.index);
      }
    });
    _loadUserAndData();
    _initializeOneSignal();
    _initializeConnectivity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (var controller in _controllers) {
      controller.dispose();
    }
    _rangoController.dispose();
    _searchController.dispose();
    _pollingTimer?.cancel();
    _persistDebounce?.cancel();
    _fallbackPendiente?.cancel();
    _tabController.dispose();
    _estacionamientosLiberando.clear();
    _connectivitySubscription?.cancel();
    _notificationStreamSubscription?.cancel();
    _wsEstacionesSub?.cancel();
    _wsTarjetasSub?.cancel();
    _wsEstadoSub?.cancel();
    super.dispose();
  }

  /// Flag: indica si hubo cambios WS mientras la app estaba en background.
  bool _hayDatosPendientesUI = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App minimizada: mantener WS vivo, solo suspender UI
        _appEnSegundoPlano = true;
        _pollingTimer?.cancel();
        ServicioWebSocket.instancia.pausar(); // reduce heartbeat, NO cierra
        debugPrint('📱 Background — WS vivo, UI suspendida');
        break;
      case AppLifecycleState.resumed:
        _appEnSegundoPlano = false;
        // Ignorar resumed duplicados en ráfaga (< 2s entre sí)
        final ahora = DateTime.now();
        if (ahora.difference(_ultimoResumed).inSeconds < 2) {
          debugPrint('📱 Foreground — duplicado ignorado');
          break;
        }
        _ultimoResumed = ahora;
        debugPrint('📱 Foreground — restaurando UI');
        _reanudarOperaciones();
        break;
      case AppLifecycleState.inactive:
        // Transición breve (ej: llamada entrante) — no hacer nada
        break;
      case AppLifecycleState.detached:
        // App siendo destruida: cerrar todo
        _appEnSegundoPlano = true;
        _pollingTimer?.cancel();
        _wsEstadoSub?.cancel();
        ServicioWebSocket.instancia.desconectar();
        _wsConectado = false;
        debugPrint('📱 Detached — WS cerrado');
        break;
    }
  }

  void _reanudarOperaciones() {
    if (!mounted) return;
    final ws = ServicioWebSocket.instancia;
    ws.reanudar(); // restaura heartbeat normal o reconecta

    // Si hubo datos WS en background, refrescar UI de una sola vez
    if (_hayDatosPendientesUI) {
      _hayDatosPendientesUI = false;
      setState(() {
        _filteredEstaciones = _filterEstaciones(_searchQuery);
        _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
      });
      debugPrint('🔄 UI sincronizada con datos acumulados en background');
    }

    // Si WS no reconectó, activar fallback (solo 1 timer a la vez)
    if (!_wsConectado) {
      _fallbackPendiente?.cancel();
      _fallbackPendiente = Timer(const Duration(seconds: 5), () {
        if (mounted && !_wsConectado) {
          _iniciarFallbackPolling();
        }
      });
    }
  }

  /// Conecta al WebSocket y suscribe a los canales de estaciones y tarjetas.
  /// Si el WS se cae, activa un polling HTTP más lento como fallback.
  void _iniciarWebSocket() {
    final ws = ServicioWebSocket.instancia;

    // Conectar (si ya está conectado, no hace nada)
    ws.conectar(token: _token);

    // Escuchar cambios de estado WS para activar/desactivar fallback polling
    _wsEstadoSub?.cancel();
    _wsEstadoSub = ws.onEstadoCambio.listen((conectado) {
      if (!mounted) return;
      if (conectado) {
        _wsConectado = true;
        if (!_appEnSegundoPlano) _cancelarFallbackPolling();
        debugPrint('🟢 WS conectado — polling HTTP desactivado');
      } else {
        _wsConectado = false;
        if (!_appEnSegundoPlano) {
          debugPrint('🔴 WS desconectado — activando fallback polling');
          _iniciarFallbackPolling();
        }
      }
    });

    // Suscribirse a canales
    _wsEstacionesSub?.cancel();
    _wsEstacionesSub = ws.escuchar('estaciones').listen((evento) {
      if (!mounted) return;
      _wsConectado = true;
      if (!_appEnSegundoPlano) _cancelarFallbackPolling();
      _procesarEventoWsEstaciones(evento);
    });

    _wsTarjetasSub?.cancel();
    _wsTarjetasSub = ws.escuchar('tarjetas').listen((evento) {
      if (!mounted) return;
      _wsConectado = true;
      if (!_appEnSegundoPlano) _cancelarFallbackPolling();
      _procesarEventoWsTarjetas(evento);
    });

    ws.suscribir('estaciones');
    ws.suscribir('tarjetas');

    // Solo iniciar fallback polling si WS no conecta en 5 segundos
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_wsConectado) {
        _iniciarFallbackPolling();
      }
    });
  }

  /// Procesa eventos de estaciones recibidos por WebSocket.
  void _procesarEventoWsEstaciones(WsEvento evento) {
    try {
      if (evento.accion == 'snapshot' && evento.datos is List) {
        // Snapshot completo de estaciones — merge protegido
        final lista = (evento.datos as List)
            .map((e) => Estacionamiento.fromJson(e as Map<String, dynamic>))
            .toList();
        lista.sort((a, b) => a.numero.compareTo(b.numero));

        // Proteger estaciones con operaciones en curso o tarjeta activa
        // para no revertir cambios locales que aún no confirmó el servidor.
        if (_estaciones.isNotEmpty) {
          final mapaLocal = {for (final e in _estaciones) e.id: e};
          for (var i = 0; i < lista.length; i++) {
            final remoto = lista[i];
            // No sobreescribir si hay operación local en curso
            if (_enProceso.contains(remoto.id)) {
              final local = mapaLocal[remoto.id];
              if (local != null) lista[i] = local;
              continue;
            }
            // No revertir ocupado→libre si hay tarjeta activa local
            final local = mapaLocal[remoto.id];
            if (local != null &&
                local.estado == true &&
                remoto.estado == false &&
                _estacionamientosTarjeta.any(
                  (t) => t.estacionId == remoto.id,
                )) {
              debugPrint(
                '🛡️ WS snapshot: protegiendo estación #${local.numero} '
                '(tiene tarjeta activa)',
              );
              lista[i] = local;
            }
          }
        }

        if (mounted) {
          // Detectar si hubo cambios reales antes de reconstruir UI
          bool hayCambios = lista.length != _estaciones.length;
          if (!hayCambios) {
            for (int i = 0; i < lista.length; i++) {
              if (lista[i].id != _estaciones[i].id ||
                  lista[i].estado != _estaciones[i].estado ||
                  lista[i].placa != _estaciones[i].placa) {
                hayCambios = true;
                break;
              }
            }
          }
          if (hayCambios || _isLoading) {
            _estaciones = lista;
            if (_appEnSegundoPlano) {
              _hayDatosPendientesUI = true;
            } else {
              setState(() {
                _filteredEstaciones = _filterEstaciones(_searchQuery);
                _rangedEstaciones = _computeRangedEstaciones(
                  _filteredEstaciones,
                );
                if (_isLoading) _isLoading = false;
              });
            }
          }
        }
        unawaited(_persistirCacheCompleto());
      } else if (evento.accion == 'update' && evento.datos is Map) {
        // Actualización de una estación específica
        final nuevo = Estacionamiento.fromJson(
          Map<String, dynamic>.from(evento.datos as Map),
        );
        if (_enProceso.contains(nuevo.id)) return;

        // Protección anti-reversión: no liberar si hay tarjeta activa local.
        // El servidor podría enviar estado=false por una race condition o
        // snapshot parcial; la liberación real llega con tarjetas/delete.
        final actual = _estaciones.where((e) => e.id == nuevo.id).firstOrNull;
        if (actual != null &&
            actual.estado == true &&
            nuevo.estado == false &&
            _estacionamientosTarjeta.any((t) => t.estacionId == nuevo.id)) {
          debugPrint(
            '🛡️ WS update: bloqueando liberación de estación '
            '#${actual.numero} (tiene tarjeta activa)',
          );
          return;
        }

        if (mounted) {
          // Actualizar datos internos siempre (foreground y background)
          var idx = _estaciones.indexWhere((e) => e.id == nuevo.id);
          if (idx == -1) {
            idx = _estaciones.indexWhere((e) => e.numero == nuevo.numero);
          }
          if (idx != -1) {
            _estaciones[idx] = nuevo;
          } else {
            if (!_estaciones.any((e) => e.numero == nuevo.numero)) {
              _estaciones.add(nuevo);
              _estaciones.sort((a, b) => a.numero.compareTo(b.numero));
            }
          }
          if (_appEnSegundoPlano) {
            _hayDatosPendientesUI = true;
          } else {
            setState(() {
              _filteredEstaciones = _filterEstaciones(_searchQuery);
              _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
            });
          }
        }
        unawaited(_persistirCacheCompleto());
      }
    } catch (e) {
      debugPrint('⚠️ Error procesando WS estaciones: $e');
    }
  }

  /// Procesa eventos de tarjetas recibidos por WebSocket.
  void _procesarEventoWsTarjetas(WsEvento evento) {
    try {
      if (evento.accion == 'snapshot' && evento.datos is List) {
        final lista = (evento.datos as List)
            .map(
              (e) =>
                  Estacionamiento_Tarjeta.fromJson(e as Map<String, dynamic>),
            )
            .where((t) => t.estacionId > 0)
            .toList();

        // Proteger tarjetas cuya estación tiene una operación en curso
        if (_enProceso.isNotEmpty) {
          final tarjetasProtegidas = _estacionamientosTarjeta
              .where((t) => _enProceso.contains(t.estacionId))
              .toList();
          for (final tp in tarjetasProtegidas) {
            if (!lista.any((t) => t.estacionId == tp.estacionId)) {
              lista.add(tp);
            }
          }
        }

        // Detectar cambios reales
        final idsActuales = _estacionamientosTarjeta
            .map((t) => t.estacionId)
            .toSet();
        final idsNuevos = lista.map((t) => t.estacionId).toSet();
        final hayCambiosTarjetas =
            idsActuales.length != idsNuevos.length ||
            !idsActuales.containsAll(idsNuevos);

        if (hayCambiosTarjetas && mounted) {
          _estacionamientosTarjeta = lista;
          if (_appEnSegundoPlano) {
            _hayDatosPendientesUI = true;
          } else {
            setState(() {});
          }
        }
        unawaited(_persistirCacheCompleto());
      } else if (evento.accion == 'update' && evento.datos is Map) {
        final tarjeta = Estacionamiento_Tarjeta.fromJson(
          Map<String, dynamic>.from(evento.datos as Map),
        );
        if (tarjeta.estacionId <= 0) return;
        if (_enProceso.contains(tarjeta.estacionId)) return;
        if (mounted) {
          final idx = _estacionamientosTarjeta.indexWhere(
            (t) => t.estacionId == tarjeta.estacionId,
          );
          if (idx == -1) {
            _estacionamientosTarjeta.add(tarjeta);
          } else {
            _estacionamientosTarjeta[idx] = tarjeta;
          }
          if (_appEnSegundoPlano) {
            _hayDatosPendientesUI = true;
          } else {
            setState(() {});
          }
        }
        unawaited(_persistirCacheCompleto());
      } else if (evento.accion == 'delete' && evento.datos is Map) {
        final estacionId = (evento.datos as Map)['estacion'] as int?;
        if (estacionId != null && !_enProceso.contains(estacionId) && mounted) {
          _estacionamientosTarjeta.removeWhere(
            (t) => t.estacionId == estacionId,
          );
          if (_appEnSegundoPlano) {
            _hayDatosPendientesUI = true;
          } else {
            setState(() {});
          }
          unawaited(_persistirCacheCompleto());
        }
      } else if (evento.accion == 'tiempo' && evento.datos is Map) {
        final num = (evento.datos as Map)['numero'] as int?;
        final tiempo = (evento.datos as Map)['tiempo'] as int?;
        if (num != null && tiempo != null && mounted) {
          _tiemposTarjeta[num] = tiempo;
          if (_appEnSegundoPlano) {
            _hayDatosPendientesUI = true;
          } else {
            setState(() {});
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error procesando WS tarjetas: $e');
    }
  }

  /// Polling HTTP lento como fallback cuando el WebSocket no está disponible.
  void _iniciarFallbackPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_fallbackPollingInterval, (_) {
      if (mounted && !_appEnSegundoPlano && !_wsConectado) {
        _actualizarDatosSilencioso();
      }
    });
  }

  void _cancelarFallbackPolling() {
    _pollingTimer?.cancel();
  }

  /// Refresco silencioso automático (fallback polling): sincroniza estaciones y tarjetas.
  /// Solo se ejecuta cuando el WS está caído. No descarga /api/tarjeta/ para ahorrar datos.
  Future<void> _actualizarDatosSilencioso() async {
    if (_appEnSegundoPlano || !mounted || _wsConectado) return;
    await _sincronizarTarjetasSilencioso();
  }

  /// Refresco completo manual (botón): descarga estacionamientos + tarjetas.
  Future<void> _refrescarManual() async {
    if (_isRefreshing || _appEnSegundoPlano || !mounted) return;
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty || results.first == ConnectivityResult.none) return;
      if (mounted) setState(() => _isRefreshing = true);
      await Future.wait([
        _fetchAndCacheEstacionamientos(),
        _fetchAndCacheEstacionamientosTarjeta(),
        _fetchAndCacheTarjetasTiempo(),
      ]);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Sincroniza estacionamientos y tarjetas vía HTTP.
  /// Solo se debe llamar cuando el WebSocket NO está activo (fallback).
  Future<void> _sincronizarTarjetasSilencioso() async {
    if (_appEnSegundoPlano || !mounted || _wsConectado) return;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isEmpty ||
          connectivity.first == ConnectivityResult.none) {
        return;
      }

      // Fetchear ambos endpoints en paralelo
      final responses = await Future.wait([
        fetchEstacionamientos(
          token: _token,
        ).timeout(const Duration(seconds: 8)),
        fetchEstacionamientoTarjeta(
          token: _token,
        ).timeout(const Duration(seconds: 8)),
      ]);

      final nuevasEstaciones = responses[0] as List<Estacionamiento>;
      final nuevasTarjetas = (responses[1] as List<Estacionamiento_Tarjeta>)
          .where((t) => t.estacionId > 0)
          .toList();

      // ---- Diff de estacionamientos (fuente de verdad para estado/placa) ----
      // Ignorar IDs que tienen una operación de registro/liberación en curso
      // para evitar sobreescribir cambios locales antes de que el servidor confirme.
      final mapaEstActual = {for (final e in _estaciones) e.id: e};
      final List<Estacionamiento> estacionesCambiadas = [];
      for (final nuevo in nuevasEstaciones) {
        if (_enProceso.contains(nuevo.id)) continue;
        final actual = mapaEstActual[nuevo.id];
        // Protección adicional: no revertir a libre si hay registro local activo.
        if (actual != null &&
            actual.estado == true &&
            nuevo.estado == false &&
            _estacionamientosTarjeta.any((t) => t.estacionId == nuevo.id)) {
          continue;
        }
        if (actual == null ||
            actual.estado != nuevo.estado ||
            actual.placa != nuevo.placa) {
          estacionesCambiadas.add(nuevo);
        }
      }

      // ---- Diff de tarjetas ----
      final mapaTarjetaActual = {
        for (final t in _estacionamientosTarjeta) t.estacionId: t,
      };
      final mapaTarjetaNuevo = {
        for (final t in nuevasTarjetas) t.estacionId: t,
      };
      final List<int> tarjetasLiberadas = [];
      final List<Estacionamiento_Tarjeta> tarjetasActualizadas = [];
      for (final id in mapaTarjetaActual.keys) {
        if (!mapaTarjetaNuevo.containsKey(id)) tarjetasLiberadas.add(id);
      }
      for (final entry in mapaTarjetaNuevo.entries) {
        final actual = mapaTarjetaActual[entry.key];
        final nuevo = entry.value;
        if (actual == null ||
            actual.placa != nuevo.placa ||
            actual.horaSalida != nuevo.horaSalida ||
            actual.horaEntrada != nuevo.horaEntrada ||
            actual.fecha != nuevo.fecha) {
          tarjetasActualizadas.add(nuevo);
        }
      }

      if (estacionesCambiadas.isEmpty &&
          tarjetasLiberadas.isEmpty &&
          tarjetasActualizadas.isEmpty) {
        // Sin diff: persistir igualmente para mantener caché fresca.
        unawaited(_persistirCacheCompleto());
        return;
      }

      if (!mounted || _appEnSegundoPlano) return;

      setState(() {
        // Aplicar cambios de estado de estacionamientos (fuente de verdad)
        for (final e in estacionesCambiadas) {
          // Buscar por id o por numero para evitar duplicados por caché corrupto
          var idx = _estaciones.indexWhere((s) => s.id == e.id);
          if (idx == -1) {
            idx = _estaciones.indexWhere((s) => s.numero == e.numero);
          }
          if (idx != -1) {
            _estaciones[idx] = e;
          }
        }
        // Aplicar cambios de tarjetas
        _estacionamientosTarjeta.removeWhere(
          (t) => tarjetasLiberadas.contains(t.estacionId),
        );
        for (final t in tarjetasActualizadas) {
          final idx = _estacionamientosTarjeta.indexWhere(
            (e) => e.estacionId == t.estacionId,
          );
          if (idx == -1) {
            _estacionamientosTarjeta.add(t);
          } else {
            _estacionamientosTarjeta[idx] = t;
          }
        }
        _filteredEstaciones = _filterEstaciones(_searchQuery);
        _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'estacionamientos',
        json.encode(_estaciones.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        'estacionamientos_tarjeta',
        json.encode(_estacionamientosTarjeta.map((e) => e.toJson()).toList()),
      );

      debugPrint(
        '🔄 Sync: ${estacionesCambiadas.length} est, +${tarjetasActualizadas.length} tar, -${tarjetasLiberadas.length} lib',
      );
    } catch (e) {
      debugPrint('⚠️ Sincronización silenciosa: $e');
    }
  }

  void _initializeConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final result = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      debugPrint('📡 Estado de conectividad: $result');
      if (result != ConnectivityResult.none && mounted && !_appEnSegundoPlano) {
        _reintentarConexion();
      }
    });
  }

  void _reintentarConexion() {
    if (!mounted || _appEnSegundoPlano) return;
    // Throttle: máximo una vez cada 15 segundos
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoReintento).inSeconds < 15) return;
    _ultimoReintento = ahora;
    debugPrint('🔄 Red recuperada — reintentando WS...');
    // Prioridad: reconectar WS. Si ya está conectado, no hace nada.
    // Solo sincronizar HTTP si WS sigue caído después de un breve delay.
    final ws = ServicioWebSocket.instancia;
    if (!ws.conectado) {
      ws.reanudar();
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_wsConectado && !_appEnSegundoPlano) {
          _sincronizarTarjetasSilencioso();
        }
      });
    }
  }

  // Inicializar OneSignal y configurar el manejo de notificaciones
  void _initializeOneSignal() {
    // Solo en Android/iOS
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      // Configurar el manejador de notificaciones recibidas
      OneSignal.Notifications.addClickListener(_handleNotificationClicked);
      debugPrint('✅ OneSignal inicializado correctamente');
    } catch (e) {
      debugPrint('❌ Error al inicializar OneSignal: $e');
    }
  }

  // Manejar clics en notificaciones
  void _handleNotificationClicked(OSNotificationClickEvent event) {
    debugPrint('👆 Notificación clickeada: ${event.notification.body}');

    // Procesar la notificación cuando el usuario hace clic
    _processNotification(event.notification);
  }

  // Procesar la notificación y actualizar los datos
  void _processNotification(OSNotification notification) {
    try {
      final additionalData = notification.additionalData;
      debugPrint('📨 Datos adicionales de la notificación: $additionalData');

      // Verificar si la notificación está relacionada con estacionamientos
      if (additionalData != null) {
        final tipo = additionalData['tipo']?.toString() ?? '';
        final estacionId = additionalData['estacionId']?.toString();
        final accion = additionalData['accion']?.toString() ?? '';

        debugPrint(
          '🔍 Analizando notificación - Tipo: $tipo, EstacionId: $estacionId, Acción: $accion',
        );

        // Si es una notificación relacionada con estacionamientos, actualizar datos
        if (tipo.contains('estacionamiento') ||
            accion.contains('actualizar') ||
            accion.contains('liberar') ||
            accion.contains('registrar')) {
          _handleEstacionamientoUpdate();
        }
      } else {
        // Si no hay datos adicionales específicos, pero el cuerpo sugiere actualización
        final body = notification.body?.toLowerCase() ?? '';
        if (body.contains('estacionamiento') ||
            body.contains('actualiz') ||
            body.contains('liber') ||
            body.contains('registr')) {
          _handleEstacionamientoUpdate();
        }
      }
    } catch (e) {
      debugPrint('❌ Error al procesar notificación: $e');
    }
  }

  // Manejar la actualización de estacionamientos desde notificación
  void _handleEstacionamientoUpdate() {
    debugPrint('🔄 Actualizando datos por notificación...');

    if (mounted && !_appEnSegundoPlano) {
      // Mostrar mensaje de actualización
      _showCustomSnackBar(
        'Actualizando información de estacionamientos...',
        isWarning: true,
      );

      // Forzar actualización de todos los datos
      _forceRefreshData();
    }
  }

  // Forzar actualización de datos (llamada desde notificaciones push).
  // Si el WS está activo, los datos ya llegan en tiempo real — no hacer HTTP.
  // Solo forzar HTTP si el WS está caído.
  DateTime _ultimoForceRefresh = DateTime(2000);
  void _forceRefreshData() async {
    if (_appEnSegundoPlano || !mounted) return;
    // Throttle: máximo una vez cada 30 segundos
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoForceRefresh).inSeconds < 30) return;
    _ultimoForceRefresh = ahora;

    if (_wsConectado) {
      // WS activo: los datos ya están actualizados en tiempo real.
      debugPrint('📨 Notificación recibida — WS activo, sin HTTP extra');
      return;
    }
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      await _sincronizarTarjetasSilencioso();
      debugPrint('✅ Datos actualizados por notificación (fallback HTTP)');
    } catch (e) {
      debugPrint('⚠️ _forceRefreshData: $e');
    }
  }

  bool _estaDeshabilitado(Estacionamiento estacion) {
    return estacion.direccion.contains('(') && estacion.direccion.contains(')');
  }

  Future<void> _loadRangoPreferencias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rangoGuardado = prefs.getString('rango_estacionamientos') ?? '';

      if (mounted && !_appEnSegundoPlano) {
        setState(() {
          _rangoEstacionamientos = rangoGuardado;
          _rangoController.text = rangoGuardado;
        });
        if (rangoGuardado.isNotEmpty) {
          _aplicarRangoEstacionamientos();
        }
      }
    } catch (e) {
      debugPrint('Error cargando rango de estacionamientos: $e');
    }
  }

  Future<void> _guardarRangoPreferencias(String rango) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rango_estacionamientos', rango);
      debugPrint('✅ Rango guardado en preferencias: $rango');
    } catch (e) {
      debugPrint('❌ Error guardando rango: $e');
      if (mounted && !_appEnSegundoPlano) {
        _showCustomSnackBar('Error al guardar el rango: $e', isError: true);
      }
    }
  }

  void _aplicarRangoEstacionamientos() {
    if (_rangoEstacionamientos.isEmpty) {
      setState(() {
        _rangedEstaciones = _filteredEstaciones;
      });
      return;
    }

    try {
      final partes = _rangoEstacionamientos.split('-');
      if (partes.length != 2) {
        _showCustomSnackBar(
          'Formato inválido. Use: inicio-fin (ej: 1-10)',
          isError: true,
        );
        return;
      }

      final inicio = int.tryParse(partes[0].trim());
      final fin = int.tryParse(partes[1].trim());

      if (inicio == null || fin == null) {
        _showCustomSnackBar(
          'Los valores deben ser números válidos',
          isError: true,
        );
        return;
      }

      if (inicio > fin) {
        _showCustomSnackBar(
          'El inicio no puede ser mayor al fin',
          isError: true,
        );
        return;
      }

      final estacionesEnRango = _filteredEstaciones.where((estacion) {
        return estacion.numero >= inicio && estacion.numero <= fin;
      }).toList();

      setState(() {
        _rangedEstaciones = estacionesEnRango;
      });
    } catch (e) {
      _showCustomSnackBar('Error al aplicar el rango: $e', isError: true);
    }
  }

  void _limpiarRango() {
    _rangoController.clear();
    _guardarRangoPreferencias('');
    setState(() {
      _rangoEstacionamientos = '';
      _rangedEstaciones = _filteredEstaciones;
    });
    _showCustomSnackBar(
      'Rango limpiado - Mostrando todos los estacionamientos',
    );
  }

  /// Calcula la lista de estacionamientos filtrada por rango sin efectos de UI.
  /// Llamar directamente dentro de setState para evitar setState anidados.
  List<Estacionamiento> _computeRangedEstaciones(
    List<Estacionamiento> filtered,
  ) {
    if (_rangoEstacionamientos.isEmpty) return filtered;
    final partes = _rangoEstacionamientos.split('-');
    if (partes.length != 2) return filtered;
    final inicio = int.tryParse(partes[0].trim());
    final fin = int.tryParse(partes[1].trim());
    if (inicio == null || fin == null || inicio > fin) return filtered;
    return filtered
        .where((e) => e.numero >= inicio && e.numero <= fin)
        .toList();
  }

  void _loadUserAndData() async {
    try {
      // Una sola lectura de SharedPreferences para usuario + caché
      final prefs = await SharedPreferences.getInstance();

      // --- Datos de usuario ---
      final userId = prefs.getInt('id') ?? 0;
      final token = prefs.getString('token') ?? '';
      if (userId == 0 && mounted && !_appEnSegundoPlano) {
        _showCustomSnackBar(
          'Error: Usuario no encontrado. Por favor, inicie sesión nuevamente.',
          isError: true,
        );
      }

      // --- Datos de caché: estacionamientos ---
      final jsonString = prefs.getString('estacionamientos');
      List<Estacionamiento> cachedEstaciones = [];
      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        final parsed = jsonList
            .map((e) => Estacionamiento.fromJson(e))
            .toList();
        // Deduplicar por numero (puede haber datos corruptos en caché antigua)
        final seen = <int>{};
        cachedEstaciones = parsed.where((e) => seen.add(e.numero)).toList();
        cachedEstaciones.sort((a, b) => a.numero.compareTo(b.numero));
      }

      // --- Datos de caché: tarjetas ---
      final tarjetasJsonString = prefs.getString('estacionamientos_tarjeta');
      List<Estacionamiento_Tarjeta> cachedTarjetas = [];
      if (tarjetasJsonString != null) {
        final List<dynamic> tarjetasJsonList = json.decode(tarjetasJsonString);
        cachedTarjetas = tarjetasJsonList
            .map((e) => _parseEstacionamientoTarjetaFromJson(e))
            .where((e) => e != null)
            .cast<Estacionamiento_Tarjeta>()
            .toList();
      }

      // --- Datos de caché: tarjetas tiempo (numero → minutos consumidos) ---
      final tarjetasTiempoStr = prefs.getString('tarjetas_tiempo');
      Map<int, int> cachedTiemposTarjeta = {};
      if (tarjetasTiempoStr != null) {
        final Map<String, dynamic> decoded = json.decode(tarjetasTiempoStr);
        cachedTiemposTarjeta = decoded.map(
          (k, v) => MapEntry(int.parse(k), (v as num).toInt()),
        );
      }

      // --- Datos de caché: nombres de usuarios ---
      final usuariosRaw = prefs.getString('cache_admin_usuarios');
      Map<int, String> nombresMap = {};
      if (usuariosRaw != null) {
        final List<dynamic> usuariosList = json.decode(usuariosRaw);
        for (final u in usuariosList) {
          if (u is Map<String, dynamic> && u['id'] != null) {
            final nombreCompleto =
                '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
            final partes = nombreCompleto.split(' ');
            // nombre[0] = primer nombre, nombre[2] = primer apellido
            final corto = partes.length >= 3
                ? '${partes[0]} ${partes[2]}'
                : partes.isNotEmpty
                ? partes.first
                : '';
            nombresMap[u['id'] as int] = corto.isNotEmpty
                ? corto
                : (u['username'] ?? 'Usuario');
          }
        }
      }

      // --- Rango ---
      final rangoGuardado = prefs.getString('rango_estacionamientos') ?? '';

      // Un único setState: la pantalla pasa de loading a datos en un solo frame
      if (!mounted) return;
      setState(() {
        _usuario = userId;
        _token = token;
        if (cachedEstaciones.isNotEmpty) {
          _estaciones = cachedEstaciones;
          _rangoEstacionamientos = rangoGuardado;
          _rangoController.text = rangoGuardado;
          _filteredEstaciones = _filterEstaciones(_searchQuery);
          _rangedEstaciones = _filteredEstaciones;
          _isLoading = false;
        }
        if (cachedTarjetas.isNotEmpty) {
          _estacionamientosTarjeta = cachedTarjetas;
        }
        if (cachedTiemposTarjeta.isNotEmpty) {
          _tiemposTarjeta = cachedTiemposTarjeta;
        }
        if (nombresMap.isNotEmpty) {
          _nombresUsuarios = nombresMap;
        }
      });

      if (cachedTarjetas.isNotEmpty) {
        _verificarTiemposExpiradosAlInicio();
      }

      // --- Descarga en background ---
      if (_appEnSegundoPlano || !mounted) return;

      final tieneCache = jsonString != null;
      if (!tieneCache) {
        // Primera vez sin caché: descargar todo por HTTP, luego activar WS.
        unawaited(
          Future.wait([
                _fetchAndCacheEstacionamientos(),
                _fetchAndCacheEstacionamientosTarjeta(),
                _fetchAndCacheTarjetasTiempo(),
              ])
              .then((_) {
                if (mounted) _iniciarWebSocket();
              })
              .catchError((e) {
                if (mounted) _iniciarWebSocket();
              }),
        );
      } else {
        // Ya hay caché: ir directo a WebSocket — el snapshot WS traerá
        // los datos actualizados sin necesidad de HTTP adicional.
        _iniciarWebSocket();
      }
    } catch (e) {
      debugPrint('Error en _loadUserAndData: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _verificarTiemposExpiradosAlInicio() async {
    if (_appEnSegundoPlano) return;

    final ahora = DateTime.now();
    final fechaHoy = DateFormat('yyyy-MM-dd').format(ahora);

    final List<int> expirados = [];

    for (final tarjeta in _estacionamientosTarjeta) {
      if (tarjeta.estacionId <= 0 || tarjeta.fecha != fechaHoy) continue;
      try {
        final partes = tarjeta.horaSalida.split(':');
        if (partes.length >= 3) {
          final horaSalida = DateTime(
            ahora.year,
            ahora.month,
            ahora.day,
            int.parse(partes[0]),
            int.parse(partes[1]),
            int.parse(partes[2]),
          );
          if (horaSalida.isBefore(ahora)) {
            expirados.add(tarjeta.estacionId);
          }
        }
      } catch (e) {
        debugPrint(
          'Error verificando tiempo inicial para ${tarjeta.estacionId}: $e',
        );
      }
    }

    if (expirados.isEmpty) return;

    // Limpieza solo local: no llamar al servidor.
    // El polling se encarga de sincronizar el estado real desde /api/estacion/.
    if (!mounted || _appEnSegundoPlano) return;
    setState(() {
      _estacionamientosTarjeta.removeWhere(
        (t) => expirados.contains(t.estacionId),
      );
      for (final id in expirados) {
        final idx = _estaciones.indexWhere((e) => e.id == id);
        if (idx != -1) {
          _estaciones[idx] = Estacionamiento(
            id: _estaciones[idx].id,
            numero: _estaciones[idx].numero,
            direccion: _estaciones[idx].direccion,
            placa: '',
            estado: false,
          );
        }
      }
      _filteredEstaciones = _filterEstaciones(_searchQuery);
      _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
    });

    // Persistir la limpieza en caché
    unawaited(_persistirCacheCompleto());
    debugPrint(
      '🧹 ${expirados.length} tarjetas expiradas limpiadas localmente al inicio',
    );
  }

  Estacionamiento_Tarjeta? _parseEstacionamientoTarjetaFromJson(dynamic json) {
    try {
      return Estacionamiento_Tarjeta.fromJson(json);
    } catch (e) {
      debugPrint('❌ Error parseando estacionamiento tarjeta: $e');
      debugPrint('❌ JSON problemático: $json');
      return null;
    }
  }

  Future<void> _fetchAndCacheEstacionamientos() async {
    if (_appEnSegundoPlano) {
      debugPrint(
        '⏸️  App en segundo plano - Saltando actualización de estacionamientos',
      );
      return;
    }

    try {
      // Verificar conectividad antes de hacer la solicitud
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult != ConnectivityResult.none;

      if (!hasConnection) {
        debugPrint('📵 Sin conexión - No se pueden obtener estacionamientos');
        return;
      }

      final estaciones = await fetchEstacionamientos(token: _token).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('⏰ Timeout al obtener estacionamientos');
          throw TimeoutException(
            'Tiempo de espera agotado para obtener estacionamientos',
          );
        },
      );

      // Deduplicar por numero antes de cachear
      final seen = <int>{};
      final dedup = estaciones.where((e) => seen.add(e.numero)).toList();
      dedup.sort((a, b) => a.numero.compareTo(b.numero));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'estacionamientos',
        json.encode(dedup.map((e) => e.toJson()).toList()),
      );

      if (mounted && !_appEnSegundoPlano) {
        setState(() {
          _estaciones = dedup;
          _filteredEstaciones = _filterEstaciones(_searchQuery);
          _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
        });
      }
    } catch (e) {
      // Silencioso: actualización en background, no interrumpir al usuario.
      debugPrint('⚠️ Sync estacionamientos: $e');
    }
  }

  Future<void> _fetchAndCacheEstacionamientosTarjeta() async {
    if (_appEnSegundoPlano) {
      debugPrint(
        '⏸️  App en segundo plano - Saltando actualización de tarjetas',
      );
      return;
    }

    try {
      // Verificar conectividad antes de hacer la solicitud
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult != ConnectivityResult.none;

      if (!hasConnection) {
        debugPrint(
          '📵 Sin conexión - No se pueden obtener estacionamientos tarjeta',
        );
        return;
      }

      final tarjetas = await fetchEstacionamientoTarjeta(token: _token).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('⏰ Timeout al obtener estacionamientos tarjeta');
          throw TimeoutException(
            'Tiempo de espera agotado para obtener registros',
          );
        },
      );

      final tarjetasValidas = tarjetas.where((tarjeta) {
        final estacionId = tarjeta.estacionId;
        return estacionId > 0;
      }).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'estacionamientos_tarjeta',
        json.encode(tarjetasValidas.map((e) => e.toJson()).toList()),
      );

      if (mounted && !_appEnSegundoPlano) {
        setState(() {
          _estacionamientosTarjeta = tarjetasValidas;
        });
      }
    } catch (e) {
      // Error silencioso: es una sincronización en background.
      // No interrumpir al usuario con snackbars por fallos de red temporales.
      debugPrint('⚠️ Sync tarjetas: $e');
    }
  }

  /// Descarga /api/tarjeta/ y actualiza el mapa {numero → tiempo consumido}.
  /// Se llama en cada ciclo de polling para mantener el saldo siempre actualizado.
  Future<void> _fetchAndCacheTarjetasTiempo() async {
    if (_appEnSegundoPlano || !mounted) return;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.isEmpty ||
          connectivity.first == ConnectivityResult.none) {
        return;
      }
      final mapa = await fetchTarjetasTiempo(
        token: _token,
      ).timeout(const Duration(seconds: 10));
      if (mapa.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'tarjetas_tiempo',
        json.encode(mapa.map((k, v) => MapEntry(k.toString(), v))),
      );
      if (mounted && !_appEnSegundoPlano) {
        setState(() => _tiemposTarjeta = mapa);
      }
    } catch (e) {
      debugPrint('⚠️ Sync tarjetas_tiempo: $e');
    }
  }

  Future<void> _liberarEstacionamientoExpirado(int estacionId) async {
    // Bloquear el polling para que no sobreescriba el estado local mientras
    // esperamos la confirmación del servidor.
    _enProceso.add(estacionId);
    try {
      debugPrint('🔄 Liberando estacionamiento expirado: $estacionId');

      _updateUIAfterChange(estacionId, false, '');

      await _updateEstacionamientoEstadoLocal(
        estacionId: estacionId,
        estado: false,
        placa: '',
      );

      try {
        // Solo intentar liberar en servidor si la app está activa y hay conexión
        if (!_appEnSegundoPlano) {
          final connectivityResult = await Connectivity().checkConnectivity();
          final hasConnection = connectivityResult != ConnectivityResult.none;

          if (hasConnection) {
            await actualizarRegistro(
              estacionId: estacionId,
              placa: '',
              estado: false,
              token: _token,
            ).timeout(const Duration(seconds: 10));
            debugPrint('✅ Estacionamiento $estacionId liberado en servidor');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error al liberar en servidor: $e');
      }

      if (mounted && !_appEnSegundoPlano) {
        setState(() {
          _estacionamientosTarjeta.removeWhere(
            (tarjeta) => tarjeta.estacionId == estacionId,
          );
        });
      }

      debugPrint('✅ Estacionamiento $estacionId liberado por tiempo expirado');
    } catch (e) {
      debugPrint('❌ Error al liberar estacionamiento expirado $estacionId: $e');
    } finally {
      // Mantener guardia 2s para que el WS broadcast llegue
      Future.delayed(
        const Duration(seconds: 2),
        () => _enProceso.remove(estacionId),
      );
    }
  }

  Widget _buildTab(String label, int count, Color color) {
    return Tab(
      height: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showCustomSnackBar(
    String message, {
    bool isError = false,
    bool isWarning = false,
  }) {
    if (!mounted || _appEnSegundoPlano) return;

    final Color backgroundColor = isError
        ? errorColor
        : isWarning
        ? warningColor
        : successColor;
    final IconData icon = isError
        ? Icons.error_outline
        : isWarning
        ? Icons.warning_amber
        : Icons.check_circle;
    final String title = isError
        ? 'Error'
        : isWarning
        ? 'Advertencia'
        : 'Éxito';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Índice de tab → filtro de estado.
  void _cambiarFiltroTab(int index) {
    const estados = ['todos', 'disponibles', 'ocupados', 'deshabilitados'];
    if (index < 0 || index >= estados.length) return;
    setState(() {
      _filtroEstado = estados[index];
      _filteredEstaciones = _filterEstaciones(_searchQuery);
      _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
    });
    // Al abrir "Ocupados" refrescar en background sin bloquear la UI.
    // La caché ya está visible; la sincronización actualiza silenciosamente.
    if (index == 2) {
      unawaited(_sincronizarTarjetasSilencioso());
    }
  }

  List<Estacionamiento> _filterEstaciones(String query) {
    var result = _estaciones;
    if (query.isNotEmpty) {
      result = result
          .where((e) => e.numero.toString().contains(query))
          .toList();
    }
    if (_filtroEstado == 'ocupados') {
      result = result.where((e) => e.estado && !_estaDeshabilitado(e)).toList();
    } else if (_filtroEstado == 'disponibles') {
      result = result
          .where((e) => !e.estado && !_estaDeshabilitado(e))
          .toList();
    } else if (_filtroEstado == 'deshabilitados') {
      result = result.where((e) => _estaDeshabilitado(e)).toList();
    }
    return result;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _filteredEstaciones = _filterEstaciones(value);
      _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
    });
  }

  Future<void> _updateEstacionamientoEstadoLocal({
    required int estacionId,
    required bool estado,
    required String placa,
  }) async {
    try {
      final updatedEstaciones = _estaciones.map((estacion) {
        if (estacion.id == estacionId) {
          return Estacionamiento(
            id: estacion.id,
            numero: estacion.numero,
            direccion: estacion.direccion,
            placa: estado ? placa : '',
            estado: estado,
          );
        }
        return estacion;
      }).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'estacionamientos',
        json.encode(updatedEstaciones.map((e) => e.toJson()).toList()),
      );

      if (mounted && !_appEnSegundoPlano) {
        setState(() {
          _estaciones = updatedEstaciones;
          _filteredEstaciones = _filterEstaciones(_searchQuery);
          _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);
        });
      }

      final estacion = _estaciones.firstWhere(
        (e) => e.id == estacionId,
        orElse: () => Estacionamiento(
          id: estacionId,
          numero: estacionId,
          direccion: '',
          placa: '',
          estado: estado,
        ),
      );
      debugPrint(
        '✅ Estado actualizado - Estacionamiento #${estacion.numero}: ${estado ? 'OCUPADO' : 'DISPONIBLE'}',
      );
    } catch (e) {
      debugPrint('❌ Error al actualizar estado local: $e');
      if (mounted && !_appEnSegundoPlano) {
        _showCustomSnackBar('Error al actualizar estado: $e', isError: true);
      }
    }
  }

  /// Persiste el estado actual de estacionamientos y tarjetas en SharedPreferences.
  /// Usa debounce de 2 segundos para no escribir a disco en cada evento WS.
  Future<void> _persistirCacheCompleto() async {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'estacionamientos',
          json.encode(_estaciones.map((e) => e.toJson()).toList()),
        );
        await prefs.setString(
          'estacionamientos_tarjeta',
          json.encode(_estacionamientosTarjeta.map((e) => e.toJson()).toList()),
        );
        if (_tiemposTarjeta.isNotEmpty) {
          await prefs.setString(
            'tarjetas_tiempo',
            json.encode(
              _tiemposTarjeta.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ Error al persistir caché: $e');
      }
    });
  }

  void _updateUIAfterChange(int estacionId, bool nuevoEstado, String placa) {
    if (!mounted || _appEnSegundoPlano) return;

    setState(() {
      final index = _estaciones.indexWhere((e) => e.id == estacionId);
      if (index != -1) {
        _estaciones[index] = Estacionamiento(
          id: _estaciones[index].id,
          numero: _estaciones[index].numero,
          direccion: _estaciones[index].direccion,
          placa: nuevoEstado ? placa : '',
          estado: nuevoEstado,
        );
        _filteredEstaciones = _filterEstaciones(_searchQuery);
        _rangedEstaciones = _computeRangedEstaciones(_filteredEstaciones);

        if (!nuevoEstado) {
          // noop: el countdown widget maneja su propio estado
        }
      }
    });
  }

  /// Minutos consumidos según el servidor (/api/tarjeta/). Fuente de verdad.
  /// Fallback local si aún no se descargó el catálogo de tarjetas.
  int _minutosConsumidosTarjeta(int t) {
    if (_tiemposTarjeta.containsKey(t)) return _tiemposTarjeta[t]!;
    return _estacionamientosTarjeta
        .where((r) => r.t == t)
        .fold(0, (sum, r) => sum + r.tiempo);
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinutosRestantesBarra(int minutosRestantes) {
    final double pct = (minutosRestantes / 120.0).clamp(0.0, 1.0);
    final Color barColor = pct > 0.5
        ? const Color(0xFF00C853)
        : pct > 0.2
        ? const Color(0xFFFF9100)
        : const Color(0xFFFF1744);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 14,
              color: barColor,
            ),
            const SizedBox(width: 5),
            Text(
              'Saldo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const Spacer(),
            Text(
              '$minutosRestantes / 120 min',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 7,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildReservadoContent(Estacionamiento estacion) {
    final dir = estacion.direccion;
    // Extraer nombre del reservante de paréntesis: "AVDA X (Juan Pérez)"
    String? reservadoPor;
    String direccionLimpia = dir;
    final regExp = RegExp(r'\((.+?)\)');
    final match = regExp.firstMatch(dir);
    if (match != null) {
      reservadoPor = match.group(1)?.trim();
      direccionLimpia = dir.replaceAll(regExp, '').trim();
      // Limpiar guiones sueltos al final
      if (direccionLimpia.endsWith('-')) {
        direccionLimpia = direccionLimpia
            .substring(0, direccionLimpia.length - 1)
            .trim();
      }
    }

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF1565C0).withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dirección completa
            if (direccionLimpia.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 16,
                    color: const Color(0xFF1565C0).withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      direccionLimpia,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Nombre del reservante
            if (reservadoPor != null && reservadoPor.isNotEmpty) ...[
              if (direccionLimpia.isNotEmpty) const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: const Color(0xFF1565C0).withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      reservadoPor,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Si no hay info extra, mostrar mensaje genérico
            if ((direccionLimpia.isEmpty || direccionLimpia == dir) &&
                (reservadoPor == null || reservadoPor.isEmpty)) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_clock_rounded,
                    size: 16,
                    color: const Color(0xFF1565C0).withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Espacio reservado',
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF1565C0).withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _buildEstacionCard(Estacionamiento estacion) {
    final bool estaDeshabilitado = _estaDeshabilitado(estacion);
    final bool ocupado = estacion.estado;
    final bool estaLiberando = _estacionamientosLiberando[estacion.id] == true;

    final tarjetaInfo = _estacionamientosTarjeta.firstWhere(
      (tarjeta) => tarjeta.estacionId == estacion.id,
      orElse: () => Estacionamiento_Tarjeta(
        t: 0,
        placa: '',
        fecha: '',
        horaEntrada: '',
        horaSalida: '',
        tiempo: 0,
        estacionId: 0,
        usuario: 0,
      ),
    );

    // Paleta de colores más imponente
    final Color accentColor = estaDeshabilitado
        ? const Color(0xFF1565C0) // Azul profundo
        : ocupado
        ? const Color(0xFFC62828) // Rojo intenso
        : const Color(0xFF2E7D32); // Verde bosque

    final Color headerGradientStart = estaDeshabilitado
        ? const Color(0xFF1565C0)
        : ocupado
        ? const Color(0xFF880E4F) // Magenta oscuro
        : const Color(0xFF1B5E20); // Verde profundo

    final Color headerGradientEnd = accentColor;

    final int minutosConsumidos = tarjetaInfo.t != 0
        ? _minutosConsumidosTarjeta(tarjetaInfo.t)
        : 0;
    final int minutosRestantes = (120 - minutosConsumidos).clamp(0, 120);

    return Card(
      elevation: 4,
      shadowColor: accentColor.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Encabezado con gradiente ─────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [headerGradientStart, headerGradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                // Círculo con número
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '#${estacion.numero}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Dirección con icono
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.local_parking_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Espacio #${estacion.numero}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (estacion.direccion.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                estacion.direccion,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Badge estado
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    estaDeshabilitado
                        ? Icons.lock_rounded
                        : ocupado
                        ? Icons.block_rounded
                        : Icons.check_circle_rounded,
                    size: 15,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),

          // ── Contenido ────────────────────────────────────────────
          InkWell(
            onTap: (!ocupado && !estaDeshabilitado)
                ? () {
                    if (_usuario == null) {
                      _showCustomSnackBar(
                        'Error: Usuario no disponible',
                        isError: true,
                      );
                      return;
                    }
                    _showRegistroForm(context, estacion);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Reservado: info detallada ─────────────────────
                  if (estaDeshabilitado) ...[
                    // Extraer nombre del reservante de los paréntesis
                    ..._buildReservadoContent(estacion),
                  ],

                  // ── Vehículo ocupado ──────────────────────────────
                  if (ocupado &&
                      !estaDeshabilitado &&
                      estacion.placa.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _infoChip(
                          Icons.directions_car_filled_rounded,
                          estacion.placa,
                          const Color(0xFF37474F),
                        ),
                        if (tarjetaInfo.t != 0)
                          _infoChip(
                            Icons.credit_card_rounded,
                            '#${tarjetaInfo.t}',
                            const Color(0xFF0D47A1),
                          ),
                      ],
                    ),
                    // Barra saldo de tarjeta
                    if (tarjetaInfo.t != 0) ...[
                      const SizedBox(height: 12),
                      _buildMinutosRestantesBarra(minutosRestantes),
                    ],
                  ],

                  // ── Horario ───────────────────────────────────────
                  if (ocupado &&
                      tarjetaInfo.horaEntrada.isNotEmpty &&
                      !estaDeshabilitado) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          // Entrada
                          Icon(
                            Icons.arrow_circle_right_rounded,
                            size: 18,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tarjetaInfo.horaEntrada.length >= 5
                                ? tarjetaInfo.horaEntrada.substring(0, 5)
                                : tarjetaInfo.horaEntrada,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 10),
                          // Salida
                          Icon(
                            Icons.arrow_circle_left_rounded,
                            size: 18,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tarjetaInfo.horaSalida.length >= 5
                                ? tarjetaInfo.horaSalida.substring(0, 5)
                                : tarjetaInfo.horaSalida,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          // Duración
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0D47A1),
                                  const Color(0xFF1565C0),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${tarjetaInfo.tiempo} min',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CountdownTicker(
                      horaSalida: tarjetaInfo.horaSalida,
                      fecha: tarjetaInfo.fecha,
                      tiempoTotalMinutos: tarjetaInfo.tiempo,
                      onExpired: () =>
                          _liberarEstacionamientoExpirado(estacion.id),
                    ),
                  ],

                  // ── Botón Liberar ──────────────────────────────────
                  if (ocupado && !estaDeshabilitado) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Usuario que registró
                        if (tarjetaInfo.usuario > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF4A148C,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(
                                  0xFF4A148C,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  size: 14,
                                  color: Color(0xFF4A148C),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _nombresUsuarios[tarjetaInfo.usuario] ??
                                      'ID ${tarjetaInfo.usuario}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4A148C),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D47A1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            shadowColor: const Color(
                              0xFF0D47A1,
                            ).withValues(alpha: 0.4),
                          ),
                          icon: estaLiberando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.exit_to_app_rounded, size: 18),
                          label: Text(
                            estaLiberando ? 'Liberando...' : 'Liberar',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 0.3,
                            ),
                          ),
                          onPressed: estaLiberando
                              ? null
                              : () async {
                                  setState(() {
                                    _estacionamientosLiberando[estacion.id] =
                                        true;
                                  });

                                  final tarjetaPrevia = _estacionamientosTarjeta
                                      .where((t) => t.estacionId == estacion.id)
                                      .toList();

                                  _enProceso.add(estacion.id);

                                  try {
                                    _updateUIAfterChange(
                                      estacion.id,
                                      false,
                                      '',
                                    );
                                    setState(() {
                                      _estacionamientosTarjeta.removeWhere(
                                        (t) => t.estacionId == estacion.id,
                                      );
                                    });
                                    await _persistirCacheCompleto();
                                    await actualizarRegistro(
                                      estacionId: estacion.id,
                                      placa: '',
                                      estado: false,
                                      token: _token,
                                    );
                                    _fetchAndCacheEstacionamientosTarjeta();
                                    _showCustomSnackBar(
                                      'Estacionamiento #${estacion.numero} liberado correctamente',
                                    );
                                  } catch (e) {
                                    _updateUIAfterChange(
                                      estacion.id,
                                      true,
                                      estacion.placa,
                                    );
                                    setState(() {
                                      _estacionamientosTarjeta.addAll(
                                        tarjetaPrevia,
                                      );
                                    });
                                    unawaited(_persistirCacheCompleto());
                                    _showCustomSnackBar(
                                      'Error al liberar: $e',
                                      isError: true,
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _estacionamientosLiberando.remove(
                                          estacion.id,
                                        );
                                      });
                                    }
                                    Future.delayed(
                                      const Duration(seconds: 2),
                                      () => _enProceso.remove(estacion.id),
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                  ],

                  // ── Libre: hint de toque ───────────────────────────
                  if (!ocupado && !estaDeshabilitado) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_circle_rounded,
                            size: 18,
                            color: const Color(
                              0xFF2E7D32,
                            ).withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Toca para registrar vehículo',
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(
                                0xFF2E7D32,
                              ).withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRegistroForm(BuildContext context, Estacionamiento estacion) {
    if (_estaDeshabilitado(estacion)) {
      _showCustomSnackBar(
        'Este estacionamiento no está disponible para uso',
        isError: true,
      );
      return;
    }

    if (_usuario == null) {
      _showCustomSnackBar(
        'Error: Usuario no disponible. Reinicie la aplicación.',
        isError: true,
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final placaController = TextEditingController();
    final fechaController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final horaEntradaController = TextEditingController(
      text: DateFormat('HH:mm:ss').format(DateTime.now()),
    );
    int tiempoSeleccionado = 15;
    final horaSalidaController = TextEditingController();
    final tarjetaController = TextEditingController();
    int minutosRestantesTarjeta =
        120; // se actualiza al escribir el número de tarjeta

    _controllers.addAll([
      placaController,
      fechaController,
      horaEntradaController,
      horaSalidaController,
      tarjetaController,
    ]);

    void calcularHoraSalida() {
      final parts = horaEntradaController.text.split(':');
      int h = 0, m = 0, s = 0;

      if (parts.length >= 2) {
        h = int.tryParse(parts[0]) ?? 0;
        m = int.tryParse(parts[1]) ?? 0;
        s = parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
      }

      final now = DateTime.now();
      final entrada = DateTime(now.year, now.month, now.day, h, m, s);
      final salida = entrada.add(Duration(minutes: tiempoSeleccionado));

      horaSalidaController.text = DateFormat('HH:mm:ss').format(salida);
    }

    calcularHoraSalida();

    final size = MediaQuery.of(context).size;
    String? errorModal;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          final tiemposDisponibles = List.generate(8, (i) => (i + 1) * 15);

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Container(
              constraints: BoxConstraints(maxHeight: size.height * 0.92),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── CABECERA ──────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0A1628), Color(0xFF000000)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.local_parking_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Registrar Estacionamiento',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Espacio #${estacion.numero}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── CONTENIDO SCROLLABLE ──────────────────────────────────
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sección: Tarjeta
                            _sectionLabel('Tarjeta', Icons.credit_card_rounded),
                            const SizedBox(height: 10),
                            _buildTextInput(
                              context: context,
                              controller: tarjetaController,
                              label: "Número de Tarjeta",
                              icon: Icons.credit_card,
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                final num = int.tryParse(val);
                                if (num != null && num > 0) {
                                  final consumidos = _minutosConsumidosTarjeta(
                                    num,
                                  );
                                  setStateModal(() {
                                    minutosRestantesTarjeta = (120 - consumidos)
                                        .clamp(0, 120);
                                    errorModal = null;
                                  });
                                } else {
                                  setStateModal(() {
                                    minutosRestantesTarjeta = 120;
                                    errorModal = null;
                                  });
                                }
                              },
                            ),
                            // Saldo de tarjeta en tiempo real
                            if (tarjetaController.text.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildMinutosRestantesBarra(
                                minutosRestantesTarjeta,
                              ),
                              if (minutosRestantesTarjeta == 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.warning_rounded,
                                        size: 14,
                                        color: Colors.red.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Esta tarjeta no tiene saldo disponible',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (minutosRestantesTarjeta <
                                  tiempoSeleccionado)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 14,
                                        color: Colors.orange.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Solo quedan $minutosRestantesTarjeta min en esta tarjeta',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            const SizedBox(height: 20),

                            // Sección: Vehículo
                            _sectionLabel(
                              'Placa del vehículo',
                              Icons.directions_car_outlined,
                            ),
                            const SizedBox(height: 10),
                            _buildTextInput(
                              context: context,
                              controller: placaController,
                              label: "Placa (ABC1234)",
                              icon: Icons.directions_car,
                              onChanged: (_) {
                                if (errorModal != null) {
                                  setStateModal(() => errorModal = null);
                                }
                              },
                            ),
                            const SizedBox(height: 20),

                            // Sección: Tiempo
                            _sectionLabel(
                              'Tiempo de estacionamiento',
                              Icons.access_time_rounded,
                            ),
                            const SizedBox(height: 10),
                            // Chips de tiempo
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tiemposDisponibles.map((min) {
                                final selected = tiempoSeleccionado == min;
                                return GestureDetector(
                                  onTap: () {
                                    setStateModal(() {
                                      tiempoSeleccionado = min;
                                      calcularHoraSalida();
                                      errorModal = null;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: selected
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF0A1628),
                                                Color(0xFF1565C0),
                                              ],
                                            )
                                          : null,
                                      color: selected
                                          ? null
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: selected
                                            ? Colors.transparent
                                            : Colors.grey.shade300,
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF5E17EB,
                                                ).withValues(alpha: 0.35),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Text(
                                      min >= 60
                                          ? '${min ~/ 60}h ${min % 60 == 0 ? '' : '${min % 60}m'}'
                                                .trim()
                                          : '$min min',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                        fontWeight: selected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 20),

                            // Sección: Horarios
                            _sectionLabel('Horario', Icons.schedule_rounded),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTimeInput(
                                    context: context,
                                    controller: horaEntradaController,
                                    label: "Entrada",
                                    icon: Icons.login_rounded,
                                    onChanged: (_) => setStateModal(() {
                                      calcularHoraSalida();
                                      errorModal = null;
                                    }),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.grey.shade400,
                                    size: 20,
                                  ),
                                ),
                                Expanded(
                                  child: _buildTextInput(
                                    context: context,
                                    controller: horaSalidaController,
                                    label: "Salida",
                                    icon: Icons.logout_rounded,
                                    enabled: false,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── BOTONES FIJOS ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Banner de error inline
                        if (errorModal != null)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.red.shade300,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red.shade700,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorModal!,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Resumen rápido
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFF5E17EB,
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _resumenItem(
                                Icons.timer_outlined,
                                '$tiempoSeleccionado min',
                              ),
                              Container(
                                width: 1,
                                height: 28,
                                color: Colors.grey.shade300,
                              ),
                              _resumenItem(
                                Icons.login_rounded,
                                horaEntradaController.text.length >= 5
                                    ? horaEntradaController.text.substring(0, 5)
                                    : '--:--',
                              ),
                              Container(
                                width: 1,
                                height: 28,
                                color: Colors.grey.shade300,
                              ),
                              _resumenItem(
                                Icons.logout_rounded,
                                horaSalidaController.text.length >= 5
                                    ? horaSalidaController.text.substring(0, 5)
                                    : '--:--',
                              ),
                            ],
                          ),
                        ),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: errorModal == null
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF0A1628),
                                        Color(0xFF1565C0),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    )
                                  : null,
                              color: errorModal != null
                                  ? Colors.grey.shade300
                                  : null,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: errorModal == null
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF5E17EB,
                                        ).withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: errorModal != null
                                  ? null
                                  : () {
                                      if (!formKey.currentState!.validate()) {
                                        setStateModal(
                                          () => errorModal =
                                              'Completa todos los campos correctamente.',
                                        );
                                        return;
                                      }

                                      // Validar tiempo suficiente en la tarjeta
                                      final tarjetaNumValidar = int.tryParse(
                                        tarjetaController.text,
                                      );
                                      if (tarjetaNumValidar != null &&
                                          tarjetaNumValidar > 0) {
                                        final consumidos =
                                            _minutosConsumidosTarjeta(
                                              tarjetaNumValidar,
                                            );
                                        final restantes = 120 - consumidos;
                                        if (tiempoSeleccionado > restantes) {
                                          setStateModal(
                                            () => errorModal = restantes <= 0
                                                ? 'La tarjeta #$tarjetaNumValidar no tiene saldo disponible.'
                                                : 'Tiempo insuficiente: solo quedan $restantes min en la tarjeta.',
                                          );
                                          return;
                                        }
                                      }
                                      setStateModal(() => errorModal = null);

                                      // Capturar datos antes de cerrar el diálogo
                                      final horaEntradaFormateada =
                                          _formatearHora(
                                            horaEntradaController.text,
                                          );
                                      final horaSalidaFormateada =
                                          _formatearHora(
                                            horaSalidaController.text,
                                          );
                                      final placa = placaController.text
                                          .toUpperCase();
                                      final tarjeta = int.parse(
                                        tarjetaController.text,
                                      );
                                      final tiempoCapturado =
                                          tiempoSeleccionado;
                                      final estacionCapturado = estacion;

                                      final nuevoRegistro =
                                          Estacionamiento_Tarjeta(
                                            fecha: DateFormat(
                                              'yyyy-MM-dd',
                                            ).format(DateTime.now()),
                                            horaEntrada: horaEntradaFormateada,
                                            horaSalida: horaSalidaFormateada,
                                            tiempo: tiempoCapturado,
                                            estacionId: estacionCapturado.id,
                                            t: tarjeta,
                                            placa: placa,
                                            usuario: _usuario!,
                                          );

                                      // 1. Actualizar UI y preferencias locales inmediatamente
                                      _enProceso.add(estacionCapturado.id);
                                      _updateUIAfterChange(
                                        estacionCapturado.id,
                                        true,
                                        placa,
                                      );
                                      setState(() {
                                        final idx = _estacionamientosTarjeta
                                            .indexWhere(
                                              (t) =>
                                                  t.estacionId ==
                                                  estacionCapturado.id,
                                            );
                                        if (idx == -1) {
                                          _estacionamientosTarjeta.add(
                                            nuevoRegistro,
                                          );
                                        } else {
                                          _estacionamientosTarjeta[idx] =
                                              nuevoRegistro;
                                        }
                                        // Actualización optimista del saldo
                                        final previo =
                                            _tiemposTarjeta[tarjeta] ?? 0;
                                        _tiemposTarjeta[tarjeta] =
                                            (previo + tiempoCapturado).clamp(
                                              0,
                                              120,
                                            );
                                      });
                                      unawaited(_persistirCacheCompleto());

                                      // 2. Cerrar diálogo al instante
                                      Navigator.pop(context);
                                      _showCustomSnackBar(
                                        '✅ Estacionamiento #${estacionCapturado.numero} registrado',
                                      );

                                      // 3. Sincronizar con el servidor en background
                                      unawaited(() async {
                                        try {
                                          // Ejecutar registro de tarjeta y actualización de estación
                                          // en PARALELO para que el broadcast WS salga más rápido
                                          await Future.wait([
                                            registarEstacionamientoTarjeta(
                                              nuevoRegistro,
                                              token: _token,
                                            ),
                                            actualizarRegistro(
                                              estacionId: estacionCapturado.id,
                                              placa: placa,
                                              estado: true,
                                              token: _token,
                                            ),
                                          ]);
                                          // Actualizar tiempo de tarjeta después
                                          final totalConsumido =
                                              _minutosConsumidosTarjeta(
                                                tarjeta,
                                              );
                                          unawaited(
                                            actualizarTiempoTarjeta(
                                              tarjeta,
                                              totalConsumido,
                                              token: _token,
                                            ),
                                          );
                                          // Mantener guardia 2s para que el WS
                                          // broadcast llegue a otros dispositivos
                                          Future.delayed(
                                            const Duration(seconds: 2),
                                            () => _enProceso.remove(
                                              estacionCapturado.id,
                                            ),
                                          );
                                          _fetchAndCacheEstacionamientosTarjeta();
                                        } catch (e) {
                                          // Revertir si el servidor falla
                                          _enProceso.remove(
                                            estacionCapturado.id,
                                          );
                                          if (mounted) {
                                            _updateUIAfterChange(
                                              estacionCapturado.id,
                                              false,
                                              '',
                                            );
                                            setState(() {
                                              _estacionamientosTarjeta
                                                  .removeWhere(
                                                    (t) =>
                                                        t.estacionId ==
                                                        estacionCapturado.id,
                                                  );
                                            });
                                            unawaited(
                                              _persistirCacheCompleto(),
                                            );
                                            _showCustomSnackBar(
                                              '❌ Error al sincronizar con el servidor: $e',
                                              isError: true,
                                            );
                                          }
                                        }
                                      }());
                                    },
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Registrar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      _controllers.remove(placaController);
      _controllers.remove(fechaController);
      _controllers.remove(horaEntradaController);
      _controllers.remove(horaSalidaController);
      _controllers.remove(tarjetaController);
    });
  }

  String _formatearHora(String hora) {
    try {
      final parts = hora.split(':');
      int h = int.tryParse(parts[0]) ?? 0;
      int m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      int s = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } catch (e) {
      return DateFormat('HH:mm:ss').format(DateTime.now());
    }
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF1565C0)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A1628),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _resumenItem(IconData icon, String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF1565C0)),
        const SizedBox(height: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A1628),
          ),
        ),
      ],
    );
  }

  Widget _buildTextInput({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
  }) {
    final size = MediaQuery.of(context).size;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        maxLength: label == "Placa (ABC1234)" ? 7 : null,
        textCapitalization: label == "Placa (ABC1234)"
            ? TextCapitalization.characters
            : TextCapitalization.none,
        keyboardType: keyboardType,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        inputFormatters: label == "Placa (ABC1234)"
            ? [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(7),
                UpperCaseTextFormatter(),
              ]
            : keyboardType == TextInputType.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        onChanged: (value) {
          if (onChanged != null) onChanged(value);
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: primaryColor),
          filled: true,
          fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade200,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
          counterText: label == "Placa (ABC1234)" ? "" : null,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: size.height * 0.02,
          ),
        ),
        style: TextStyle(fontSize: size.width * 0.04),
        validator: (value) {
          if (enabled && (value == null || value.isEmpty)) {
            return 'Campo requerido';
          }
          if (label == "Placa (ABC1234)") {
            final upper = value!.toUpperCase();
            final regex = RegExp(r'^[A-Z]{3}\d{4}$');
            if (!regex.hasMatch(upper)) {
              return 'Formato inválido. Use 3 letras + 4 números (ABC1234)';
            }
          }
          if (label == "Número de Tarjeta") {
            if (value!.isEmpty) {
              return 'Número de tarjeta requerido';
            }
            final tarjetaId = int.tryParse(value);
            if (tarjetaId == null || tarjetaId <= 0) {
              return 'Número de tarjeta inválido';
            }
          }
          return null;
        },
      ),
    );
  }

  Widget _buildTimeInput({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Function(String)? onChanged,
  }) {
    final size = MediaQuery.of(context).size;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'\d|:')),
          LengthLimitingTextInputFormatter(8),
        ],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: primaryColor),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.access_time, color: Colors.grey),
            onPressed: () async {
              final parts = controller.text.split(':');
              int h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
              int m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: h, minute: m),
              );
              if (time != null) {
                controller.text =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                if (onChanged != null) onChanged(controller.text);
              }
            },
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: size.height * 0.02,
          ),
        ),
        style: TextStyle(fontSize: size.width * 0.04),
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Hora de entrada requerida';
          }
          final regex = RegExp(r'^\d{2}:\d{2}:\d{2}$');
          if (!regex.hasMatch(value)) {
            return 'Formato inválido (HH:mm:ss)';
          }
          return null;
        },
      ),
    );
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
                gradient: LinearGradient(
                  colors: [Color(0xFF0A1628), Color(0xFF000000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
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
                    'Control de Tarjetas',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Muestra el estado de ocupación de los espacios de estacionamiento y permite gestionar el ingreso y salida de vehículos.',
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
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          "Control de Tarjetas",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1628), Color(0xFF000000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Información',
            onPressed: () => _mostrarInfo(context),
          ),
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualizar ahora',
              onPressed: _refrescarManual,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Banner resumen de ocupación ─────────────────────────────────
          if (_estaciones.isNotEmpty)
            Builder(
              builder: (_) {
                final ocupados = _estaciones
                    .where((e) => e.estado && !_estaDeshabilitado(e))
                    .toList();
                final totalActivos = _estaciones
                    .where((e) => !_estaDeshabilitado(e))
                    .length;
                final hayOcupados = ocupados.isNotEmpty;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hayOcupados
                          ? [const Color(0xFF0A1628), const Color(0xFF0D3278)]
                          : [Colors.green.shade700, Colors.green.shade600],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hayOcupados
                                ? '${ocupados.length} ocupado${ocupados.length != 1 ? 's' : ''}'
                                : 'Todos libres',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'de $totalActivos espacios',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (hayOcupados) ...[
                        const SizedBox(width: 12),
                        Container(width: 1, height: 32, color: Colors.white24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: ocupados.map((e) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () => _tabController.animateTo(2),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade400.withValues(
                                          alpha: 0.3,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.red.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '#${e.numero}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          Container(
            padding: EdgeInsets.fromLTRB(
              size.width * 0.04,
              size.width * 0.04,
              size.width * 0.04,
              size.width * 0.035,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar por número de estacionamiento...",
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: size.height * 0.015,
                      horizontal: 16,
                    ),
                  ),
                  onChanged: _onSearchChanged,
                  keyboardType: TextInputType.number,
                ),

                SizedBox(height: size.height * 0.015),

                Row(
                  children: [
                    if (_rangoEstacionamientos.isNotEmpty) ...[
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.03,
                          vertical: size.height * 0.01,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.filter_alt,
                              size: size.width * 0.04,
                              color: primaryColor,
                            ),
                            SizedBox(width: size.width * 0.02),
                            Text(
                              'Rango: $_rangoEstacionamientos',
                              style: TextStyle(
                                fontSize: size.width * 0.035,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: size.width * 0.03),
                    ],

                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rangoEstacionamientos.isNotEmpty
                              ? primaryColor
                              : Colors.grey.shade200,
                          foregroundColor: _rangoEstacionamientos.isNotEmpty
                              ? Colors.white
                              : Colors.grey.shade700,
                          padding: EdgeInsets.symmetric(
                            horizontal: size.width * 0.04,
                            vertical: size.height * 0.012,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(
                          Icons.filter_alt,
                          size: size.width * 0.045,
                          color: _rangoEstacionamientos.isNotEmpty
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                        label: Text(
                          _rangoEstacionamientos.isNotEmpty
                              ? "Cambiar"
                              : "Filtrar",
                          style: TextStyle(
                            fontSize: size.width * 0.035,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          _mostrarDialogoRango(context);
                        },
                      ),
                    ),

                    const Spacer(),

                    Text(
                      '${_rangedEstaciones.length}/${_estaciones.length}',
                      style: TextStyle(
                        fontSize: size.width * 0.035,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (_estaciones.isNotEmpty) ...[
                  SizedBox(height: size.height * 0.008),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0x0D000000),
                  ),
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    dividerColor: Colors.transparent,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(
                        color: Color(0xFF0A1628),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: const Color(0xFF0A1628),
                    unselectedLabelColor: Colors.grey,
                    labelPadding: EdgeInsets.zero,
                    tabs: [
                      _buildTab('Todos', _estaciones.length, primaryColor),
                      _buildTab(
                        'Libres',
                        _estaciones
                            .where((e) => !e.estado && !_estaDeshabilitado(e))
                            .length,
                        Colors.green.shade600,
                      ),
                      _buildTab(
                        'Ocupados',
                        _estaciones
                            .where((e) => e.estado && !_estaDeshabilitado(e))
                            .length,
                        Colors.red.shade600,
                      ),
                      _buildTab(
                        'Reservados',
                        _estaciones.where((e) => _estaDeshabilitado(e)).length,
                        Colors.blue.shade600,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? Container(
                    color: const Color(0xFFF0F4FF),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: size.width * 0.28,
                            height: size.width * 0.28,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF0A1628), Color(0xFF000000)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.local_parking,
                              size: 52,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: size.height * 0.03),
                          const Text(
                            'SIMERT',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0A1628),
                              letterSpacing: 3,
                            ),
                          ),
                          SizedBox(height: size.height * 0.008),
                          const Text(
                            'Cargando estacionamientos...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF555555),
                            ),
                          ),
                          SizedBox(height: size.height * 0.035),
                          SizedBox(
                            width: size.width * 0.5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: const LinearProgressIndicator(
                                minHeight: 5,
                                backgroundColor: Color(0xFFD0D9F0),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF1565C0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _rangedEstaciones.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.1,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(size.width * 0.06),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.local_parking,
                              size: 56,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          SizedBox(height: size.height * 0.02),
                          Text(
                            _rangoEstacionamientos.isNotEmpty
                                ? "Sin resultados en el rango\n$_rangoEstacionamientos"
                                : "No se encontraron\nestacionamientos",
                            style: TextStyle(
                              fontSize: size.width * 0.04,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_rangoEstacionamientos.isNotEmpty) ...[
                            SizedBox(height: size.height * 0.02),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _limpiarRango,
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: Text(
                                "Mostrar todos",
                                style: TextStyle(fontSize: size.width * 0.04),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      _fetchAndCacheEstacionamientos();
                      _fetchAndCacheEstacionamientosTarjeta();
                    },
                    child: ListView.builder(
                      itemCount: _rangedEstaciones.length,
                      itemBuilder: (context, index) {
                        return RepaintBoundary(
                          child: _buildEstacionCard(_rangedEstaciones[index]),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoRango(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final TextEditingController rangoDialogController = TextEditingController(
      text: _rangoEstacionamientos,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.filter_alt,
              color: primaryColor,
              size: size.width * 0.06,
            ),
            SizedBox(width: size.width * 0.03),
            Text(
              "Filtrar por rango",
              style: TextStyle(fontSize: size.width * 0.045),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Ingrese el rango de estacionamientos que desea ver:",
              style: TextStyle(
                fontSize: size.width * 0.035,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: size.height * 0.01),
            Text(
              "Formato: inicio-fin (ej: 1-10)",
              style: TextStyle(
                fontSize: size.width * 0.03,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: size.height * 0.02),
            TextField(
              controller: rangoDialogController,
              decoration: InputDecoration(
                hintText: "1-10",
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.symmetric(
                  vertical: size.height * 0.02,
                  horizontal: 16,
                ),
              ),
              keyboardType: TextInputType.text,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(
              "Cancelar",
              style: TextStyle(fontSize: size.width * 0.04),
            ),
          ),
          if (_rangoEstacionamientos.isNotEmpty)
            TextButton(
              onPressed: () {
                _limpiarRango();
                Navigator.pop(context);
              },
              child: Text(
                "Limpiar",
                style: TextStyle(
                  fontSize: size.width * 0.04,
                  color: Colors.red,
                ),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final nuevoRango = rangoDialogController.text.trim();
              if (nuevoRango.isNotEmpty) {
                setState(() {
                  _rangoEstacionamientos = nuevoRango;
                  _rangoController.text = nuevoRango;
                });
                _guardarRangoPreferencias(nuevoRango);
                _aplicarRangoEstacionamientos();
              }
              Navigator.pop(context);
            },
            child: Text(
              "Aplicar",
              style: TextStyle(fontSize: size.width * 0.04),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget autocontenido para el contador regresivo de cada estacionamiento.
// Tiene su propio Timer de 1 segundo → solo se reconstruye él mismo,
// NO la pantalla completa, eliminando el jank de la versión anterior.
// ---------------------------------------------------------------------------
class _CountdownTicker extends StatefulWidget {
  final String horaSalida;
  final String fecha;
  final int tiempoTotalMinutos;
  final VoidCallback onExpired;

  const _CountdownTicker({
    required this.horaSalida,
    required this.fecha,
    required this.tiempoTotalMinutos,
    required this.onExpired,
  });

  @override
  State<_CountdownTicker> createState() => _CountdownTickerState();
}

class _CountdownTickerState extends State<_CountdownTicker> {
  static const Color _errorColor = Color(0xFFD32F2F);
  static const Color _warningColor = Color(0xFFFF9800);
  static const Color _primaryColor = Color(0xFF0A1628);
  static const Color _successColor = Color(0xFF00C853);

  late Duration _remaining;
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _calcular();
    if (!_expired) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      // Tiempo ya expirado al montar el widget (ej: app abierta después de expirar).
      // Notificar al padre en el siguiente frame para no llamar setState durante el build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired();
      });
    }
  }

  @override
  void didUpdateWidget(_CountdownTicker old) {
    super.didUpdateWidget(old);
    if (old.horaSalida != widget.horaSalida || old.fecha != widget.fecha) {
      _expired = false;
      _calcular();
      _timer?.cancel();
      if (!_expired) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onExpired();
        });
      }
    }
  }

  void _calcular() {
    final ahora = DateTime.now();
    final fechaHoy = DateFormat('yyyy-MM-dd').format(ahora);
    if (widget.fecha != fechaHoy) {
      _remaining = Duration.zero;
      _expired = true;
      return;
    }
    try {
      final p = widget.horaSalida.split(':');
      if (p.length < 3) {
        _remaining = Duration.zero;
        _expired = true;
        return;
      }
      final salida = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
      );
      _remaining = salida.difference(ahora);
      if (_remaining.inSeconds <= 0) _expired = true;
    } catch (_) {
      _remaining = Duration.zero;
      _expired = true;
    }
  }

  void _tick() {
    if (!mounted) return;
    final ahora = DateTime.now();
    try {
      final p = widget.horaSalida.split(':');
      final salida = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
      );
      setState(() => _remaining = salida.difference(ahora));
    } catch (_) {
      setState(() => _remaining = Duration.zero);
    }
    if (_remaining.inSeconds <= 0 && !_expired) {
      _expired = true;
      _timer?.cancel();
      widget.onExpired();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _color() {
    if (_remaining.isNegative) return _errorColor;
    if (_remaining.inMinutes <= 5) return _warningColor;
    if (_remaining.inMinutes <= 15) return _primaryColor;
    return _successColor;
  }

  String _formatTime() {
    if (_remaining.isNegative) return '00:00:00';
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return _remaining.inHours > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final color = _color();
    final bool expirado = _remaining.isNegative;
    final bool urgente = !expirado && _remaining.inMinutes < 2;
    final bool advertencia = !expirado && _remaining.inMinutes < 5;
    final totalSeg = widget.tiempoTotalMinutos > 0
        ? widget.tiempoTotalMinutos * 60
        : 1;
    final restanteSeg = expirado ? 0 : _remaining.inSeconds;
    final progreso = (restanteSeg / totalSeg).clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: EdgeInsets.all(size.width * 0.035),
      decoration: BoxDecoration(
        color: color.withValues(alpha: urgente ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: urgente ? 0.65 : 0.28),
          width: urgente ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    expirado
                        ? Icons.timer_off_rounded
                        : urgente
                        ? Icons.warning_rounded
                        : Icons.timer_rounded,
                    color: color,
                    size: size.width * 0.048,
                  ),
                  SizedBox(width: size.width * 0.02),
                  Text(
                    expirado ? 'TIEMPO EXPIRADO' : 'Tiempo restante',
                    style: TextStyle(
                      fontSize: size.width * 0.032,
                      fontWeight: FontWeight.w600,
                      color: color,
                      letterSpacing: expirado ? 0.5 : 0,
                    ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.03,
                  vertical: size.height * 0.005,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  _formatTime(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: size.width * 0.044,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (widget.tiempoTotalMinutos > 0) ...[
            SizedBox(height: size.height * 0.008),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 6,
                backgroundColor: color.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
          if (advertencia) ...[
            SizedBox(height: size.height * 0.007),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: color,
                  size: size.width * 0.037,
                ),
                SizedBox(width: size.width * 0.015),
                Text(
                  urgente
                      ? '¡Quedan menos de 2 minutos!'
                      : 'Quedan menos de 5 minutos',
                  style: TextStyle(
                    fontSize: size.width * 0.03,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

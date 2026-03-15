import 'dart:convert';
import 'dart:async';
import 'package:estacionamientotarifado/servicios/servicioEstacionamiento.dart';
import 'package:estacionamientotarifado/servicios/servicioEstacionamientoTarjeta.dart';
import 'package:estacionamientotarifado/tarjetas/models/Estacionamiento.dart';
import 'package:estacionamientotarifado/tarjetas/models/Tarjetas.dart';
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

  bool _isLoading = true;
  String _searchQuery = '';
  String _rangoEstacionamientos = '';
  int? _usuario;
  final Color primaryColor = const Color(0xFF001F54);
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
  static const Duration _pollingInterval = Duration(seconds: 4);

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
    _tabController.dispose();
    _estacionamientosLiberando.clear();
    _connectivitySubscription?.cancel();
    _notificationStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        _appEnSegundoPlano = true;
        debugPrint('📱 App en segundo plano - Cancelando operaciones de red');
        _cancelarOperacionesRed();
        break;
      case AppLifecycleState.resumed:
        _appEnSegundoPlano = false;
        debugPrint('📱 App en primer plano - Reanudando operaciones');
        _reanudarOperaciones();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _appEnSegundoPlano = true;
        _cancelarOperacionesRed();
        break;
      case AppLifecycleState.hidden:
        // Nuevo estado en Flutter 3.16+
        _appEnSegundoPlano = true;
        _cancelarOperacionesRed();
        break;
    }
  }

  void _cancelarOperacionesRed() {
    _pollingTimer?.cancel();
  }

  void _reanudarOperaciones() {
    if (mounted) {
      _iniciarPolling();
    }
  }

  void _iniciarPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (mounted && !_appEnSegundoPlano) {
        _actualizarDatosSilencioso();
      }
    });
  }

  /// Refresco silencioso automático (cada 4 s): sincroniza todo.
  Future<void> _actualizarDatosSilencioso() async {
    if (_appEnSegundoPlano || !mounted) return;
    await Future.wait([
      _sincronizarTarjetasSilencioso(),
      _fetchAndCacheTarjetasTiempo(),
    ]);
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

  /// Sincroniza solo las tarjetas que cambiaron — sin tocar estacionamientos.
  /// Sincroniza estacionamientos (fuente de verdad: /api/estacion/) y tarjetas.
  /// Solo aplica los cambios detectados por diff — sin reconstruir la lista completa.
  Future<void> _sincronizarTarjetasSilencioso() async {
    if (_appEnSegundoPlano || !mounted) return;
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
          final idx = _estaciones.indexWhere((s) => s.id == e.id);
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
    if (mounted && !_appEnSegundoPlano) {
      debugPrint('🔄 Reintentando conexión...');
      _sincronizarTarjetasSilencioso();
    }
  }

  // Inicializar OneSignal y configurar el manejo de notificaciones
  void _initializeOneSignal() {
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

  // Forzar actualización completa de datos (silenciosa — llamada desde notificaciones)
  void _forceRefreshData() async {
    if (_appEnSegundoPlano || !mounted) return;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return;

      // Actualizar en background sin tocar _isLoading para no ocultar los datos
      await Future.wait([
        _fetchAndCacheEstacionamientos(),
        _fetchAndCacheEstacionamientosTarjeta(),
        _fetchAndCacheTarjetasTiempo(),
      ]);
      await _loadRangoPreferencias();
      debugPrint('✅ Datos actualizados por notificación');
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
        cachedEstaciones = jsonList
            .map((e) => Estacionamiento.fromJson(e))
            .toList();
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
      });

      if (cachedTarjetas.isNotEmpty) {
        _verificarTiemposExpiradosAlInicio();
      }

      // --- Descarga en background ---
      if (_appEnSegundoPlano || !mounted) return;

      final tieneCache = jsonString != null;
      if (!tieneCache) {
        // Primera vez: descargar todo
        unawaited(
          Future.wait([
                _fetchAndCacheEstacionamientos(),
                _fetchAndCacheEstacionamientosTarjeta(),
                _fetchAndCacheTarjetasTiempo(),
              ])
              .then((_) {
                if (mounted) _iniciarPolling();
              })
              .catchError((e) {
                if (mounted) _iniciarPolling();
              }),
        );
      } else {
        // Ya hay caché: mostrar inmediatamente y sincronizar todo en background.
        unawaited(
          Future.wait([
            _sincronizarTarjetasSilencioso(),
            _fetchAndCacheTarjetasTiempo(),
          ]).then((_) => _iniciarPolling()).catchError((e) {
            debugPrint('⚠️ Sync inicial: $e');
            _iniciarPolling();
          }),
        );
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
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⏰ Timeout al obtener estacionamientos');
          throw TimeoutException(
            'Tiempo de espera agotado para obtener estacionamientos',
          );
        },
      );

      estaciones.sort((a, b) => a.numero.compareTo(b.numero));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'estacionamientos',
        json.encode(estaciones.map((e) => e.toJson()).toList()),
      );

      if (mounted && !_appEnSegundoPlano) {
        setState(() {
          _estaciones = estaciones;
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
        const Duration(seconds: 15),
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
      _enProceso.remove(estacionId);
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
  Future<void> _persistirCacheCompleto() async {
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
          json.encode(_tiemposTarjeta.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error al persistir caché: $e');
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
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
        ? Colors.orange
        : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saldo tarjeta',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            Text(
              '$minutosRestantes / 120 min',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 6,
          ),
        ),
      ],
    );
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

    final Color accentColor = estaDeshabilitado
        ? disabledColor
        : ocupado
        ? Colors.redAccent
        : const Color(0xFF00C853);

    final int minutosConsumidos = tarjetaInfo.t != 0
        ? _minutosConsumidosTarjeta(tarjetaInfo.t)
        : 0;
    final int minutosRestantes = (120 - minutosConsumidos).clamp(0, 120);

    return Card(
      elevation: 2,
      shadowColor: accentColor.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4), width: 1.5),
      ),
      color: accentColor.withValues(alpha: 0.04),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Franja lateral de color
              Container(width: 6, color: accentColor),

              // Contenido principal
              Expanded(
                child: InkWell(
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(14),
                  ),
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
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Encabezado ──────────────────────────────────
                        Row(
                          children: [
                            // Círculo con número
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accentColor,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '#${estacion.numero}',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Nombre y dirección
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Espacio #${estacion.numero}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF001F54),
                                    ),
                                  ),
                                  if (estacion.direccion.isNotEmpty)
                                    Text(
                                      estacion.direccion,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            // Badge de estado
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                estaDeshabilitado
                                    ? 'N/D'
                                    : ocupado
                                    ? 'OCUPADO'
                                    : 'LIBRE',
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Vehículo ocupado ────────────────────────────
                        if (ocupado &&
                            !estaDeshabilitado &&
                            estacion.placa.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1, thickness: 1),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _infoChip(
                                Icons.directions_car_rounded,
                                estacion.placa,
                                Colors.grey.shade700,
                              ),
                              if (tarjetaInfo.t != 0)
                                _infoChip(
                                  Icons.credit_card_rounded,
                                  'Tarjeta #${tarjetaInfo.t}',
                                  primaryColor,
                                ),
                            ],
                          ),
                          // Barra saldo de tarjeta
                          if (tarjetaInfo.t != 0) ...[
                            const SizedBox(height: 10),
                            _buildMinutosRestantesBarra(minutosRestantes),
                          ],
                        ],

                        // ── Horario ─────────────────────────────────────
                        if (ocupado &&
                            tarjetaInfo.horaEntrada.isNotEmpty &&
                            !estaDeshabilitado) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.login_rounded,
                                size: 14,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tarjetaInfo.horaEntrada.length >= 5
                                    ? tarjetaInfo.horaEntrada.substring(0, 5)
                                    : tarjetaInfo.horaEntrada,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.logout_rounded,
                                size: 14,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tarjetaInfo.horaSalida.length >= 5
                                    ? tarjetaInfo.horaSalida.substring(0, 5)
                                    : tarjetaInfo.horaSalida,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${tarjetaInfo.tiempo} min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _CountdownTicker(
                            horaSalida: tarjetaInfo.horaSalida,
                            fecha: tarjetaInfo.fecha,
                            tiempoTotalMinutos: tarjetaInfo.tiempo,
                            onExpired: () =>
                                _liberarEstacionamientoExpirado(estacion.id),
                          ),
                        ],

                        // ── Botón Liberar ────────────────────────────────
                        if (ocupado && !estaDeshabilitado) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
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
                                  : const Icon(
                                      Icons.exit_to_app_rounded,
                                      size: 18,
                                    ),
                              label: Text(
                                estaLiberando ? 'Liberando...' : 'Liberar',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: estaLiberando
                                  ? null
                                  : () async {
                                      setState(() {
                                        _estacionamientosLiberando[estacion
                                                .id] =
                                            true;
                                      });

                                      final tarjetaPrevia =
                                          _estacionamientosTarjeta
                                              .where(
                                                (t) =>
                                                    t.estacionId == estacion.id,
                                              )
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
                                        _enProceso.remove(estacion.id);
                                      }
                                    },
                            ),
                          ),
                        ],

                        // ── Libre: hint de toque ─────────────────────────
                        if (!ocupado && !estaDeshabilitado) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1, thickness: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                size: 14,
                                color: Colors.green.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Toca para registrar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade400,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                        colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
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
                                                Color(0xFF001F54),
                                                Color(0xFF5E17EB),
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
                                    onChanged: (_) => setStateModal(
                                      () => calcularHoraSalida(),
                                    ),
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
                                        Color(0xFF001F54),
                                        Color(0xFF5E17EB),
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
                                          await registarEstacionamientoTarjeta(
                                            nuevoRegistro,
                                            token: _token,
                                          );
                                          // Sincronizar tiempo real de la tarjeta
                                          // (recalculado desde todos los registros locales)
                                          final totalConsumido =
                                              _minutosConsumidosTarjeta(
                                                tarjeta,
                                              );
                                          await actualizarTiempoTarjeta(
                                            tarjeta,
                                            totalConsumido,
                                            token: _token,
                                          );
                                          await actualizarRegistro(
                                            estacionId: estacionCapturado.id,
                                            placa: placa,
                                            estado: true,
                                            token: _token,
                                          );
                                          // Servidor confirmó → ya es seguro permitir que
                                          // el polling sobreescriba este espacio.
                                          _enProceso.remove(
                                            estacionCapturado.id,
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
        Icon(icon, size: 16, color: const Color(0xFF5E17EB)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF001F54),
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
        Icon(icon, size: 16, color: const Color(0xFF5E17EB)),
        const SizedBox(height: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF001F54),
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
    String? errorText;

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
          if (label == "Placa (ABC1234)") {
            final upper = value.toUpperCase();
            final regex = RegExp(r'^[A-Z]{3}\d{4}$');
            setState(() {
              errorText = upper.length < 7
                  ? null
                  : regex.hasMatch(upper)
                  ? null
                  : 'Formato inválido. Debe ser ABC1234';
            });
          }
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
          errorText: errorText,
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
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
              colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
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
                          ? [const Color(0xFF001F54), const Color(0xFF0D3278)]
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
                        color: Color(0xFF001F54),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: const Color(0xFF001F54),
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
                        'N/D',
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
                                colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
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
                              color: Color(0xFF001F54),
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
                                  Color(0xFF5E17EB),
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
  static const Color _primaryColor = Color(0xFF001F54);
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

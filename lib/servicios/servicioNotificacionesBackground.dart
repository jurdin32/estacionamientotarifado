import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' as app;
import '../tarjetas/models/Estacionamiento.dart';
import '../tarjetas/models/Tarjetas.dart';
import '../tarjetas/views/EstacionamientoScreen.dart';

import 'httpMonitorizado.dart';
import 'servicioEstacionamiento.dart';
import 'servicioEstacionamientoTarjeta.dart';

/// Servicio que muestra una notificación persistente (ongoing) con cuenta
/// regresiva del estacionamiento más próximo a expirar.
///
/// La notificación:
/// - Muestra el tiempo restante en formato mm:ss
/// - Muestra el usuario que registró el estacionamiento
/// - Cuando llega a 0, libera el estacionamiento localmente
/// - Nunca se cierra (ongoing + recreación automática)
/// - Al tocarla, navega a Control de Tarjetas
class ServicioNotificacionesBackground {
  static Timer? _timerSync;
  static Timer? _timerLiberacion;
  static Timer? _timerNotificacion;
  static bool _inicializado = false;

  static final FlutterLocalNotificationsPlugin _notificaciones =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'estacionamiento_channel';
  static const String _channelName = 'Estacionamientos SIMERT';
  static const String _channelDesc =
      'Notificación persistente del estacionamiento más próximo a expirar';
  static const int _notificacionId = 88;

  // Cache del último estado para la cuenta regresiva
  static Estacionamiento_Tarjeta? _ultimaTarjeta;
  static int _ultimosMinutos = 0;
  static int _ultimosSegundos = 0;
  static String _ultimoUsuario = '';

  /// Inicializa el plugin de notificaciones locales
  static Future<void> _initNotificaciones() async {
    const androidSettings = AndroidInitializationSettings('ic_carrito');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notificaciones.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificacionTocada,
    );
  }

  /// Callback cuando el usuario toca la notificación persistente
  static void _onNotificacionTocada(NotificationResponse response) {
    debugPrint('👆 Notificación tocada');
    try {
      final navKey = _getNavigatorKey();
      if (navKey?.currentContext == null) return;

      Navigator.push(
        navKey!.currentContext!,
        MaterialPageRoute(builder: (_) => const EstacionamientoScreen()),
      );
    } catch (e) {
      debugPrint('⚠️ Error navegando desde notificación: $e');
    }
  }

  /// Obtiene el GlobalKey del navigator desde main.dart
  static GlobalKey<NavigatorState>? _getNavigatorKey() {
    try {
      return app.navigatorKey;
    } catch (_) {
      return null;
    }
  }

  /// Muestra o actualiza la notificación persistente con cuenta regresiva.
  /// Se llama cada segundo para actualizar el tiempo en tiempo real.
  static Future<void> _mostrarNotificacion({
    required String titulo,
    required String contenido,
  }) async {
    try {
      // Icono de carrito para notificación
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        icon: 'ic_carrito',
        largeIcon: const DrawableResourceAndroidBitmap('ic_carrito'),
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true, // No se puede deslizar para cerrar
        autoCancel: false,
        showWhen: false,
        usesChronometer: false,
        onlyAlertOnce: true,
        playSound: false,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(presentAlert: false),
      );
      await _notificaciones.show(_notificacionId, titulo, contenido, details);
    } catch (e) {
      debugPrint('⚠️ Error mostrando notificación: $e');
    }
  }

  /// Inicia los timers de sincronización, liberación y notificación.
  static Future<void> iniciarServicio() async {
    if (_inicializado) {
      debugPrint('🟢 Servicio ya inicializado');
      return;
    }
    _inicializado = true;
    debugPrint('🟢 Iniciando servicio de notificaciones y sincronización');

    try {
      // Inicializar plugin de notificaciones
      await _initNotificaciones();

      // Mostrar notificación inicial
      await _mostrarNotificacion(
        titulo: 'SIMERT Estacionamientos',
        contenido: 'Iniciando monitoreo...',
      );

      // --- SINCRONIZACIÓN INICIAL FORZADA ---
      // Al arrancar la app (después de haber sido cerrada por Android
      // o por cualquier motivo), forzamos una sincronización completa
      // con el servidor para limpiar datos viejos del caché local.
      debugPrint('🔄 Sincronización inicial forzada...');
      await _sincronizarCache();
      await _liberarExpiradosLocalmente();

      // Timer de cuenta regresiva CADA SEGUNDO para tiempo en tiempo real
      _timerNotificacion?.cancel();
      _timerNotificacion = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          _actualizarNotificacion();
        } catch (e) {
          debugPrint('⚠️ Error en timer notificación: $e');
        }
      });

      // Liberar expirados cada 30 segundos
      _timerLiberacion?.cancel();
      _timerLiberacion = Timer.periodic(const Duration(seconds: 30), (_) {
        try {
          _liberarExpiradosLocalmente();
        } catch (e) {
          debugPrint('⚠️ Error en timer liberación: $e');
        }
      });

      // Sincronizar caché con servidor cada 60 segundos
      _timerSync?.cancel();
      _timerSync = Timer.periodic(const Duration(seconds: 60), (_) {
        try {
          _sincronizarCache();
        } catch (e) {
          debugPrint('⚠️ Error en timer sincronización: $e');
        }
      });

      // Ejecutar inmediatamente la notificación para mostrar datos reales
      try {
        await _actualizarNotificacion();
      } catch (e) {
        debugPrint('⚠️ Error en actualización inmediata: $e');
      }
    } catch (e) {
      debugPrint('❌ Error inicializando servicio: $e');
      _inicializado = false;
    }
  }

  /// Detiene los timers y oculta la notificación
  static void detenerServicio() {
    _timerLiberacion?.cancel();
    _timerSync?.cancel();
    _timerNotificacion?.cancel();
    _timerLiberacion = null;
    _timerSync = null;
    _timerNotificacion = null;
    _inicializado = false;
    _notificaciones.cancel(_notificacionId);
    debugPrint('🛑 Servicio detenido');
  }

  /// Fuerza una sincronización y actualización inmediata
  static Future<void> actualizarAhora() async {
    try {
      await _sincronizarCache();
      await _liberarExpiradosLocalmente();
      await _actualizarNotificacion();
    } catch (e) {
      debugPrint('⚠️ Error en actualizarAhora: $e');
    }
  }

  /// Ejecuta la tarea de background (llamado por WorkManager incluso con app cerrada).
  /// Solo libera expirados y sincroniza caché (sin notificaciones UI).
  static Future<void> ejecutarTareaBackground() async {
    debugPrint('🔄 [Background] Ejecutando tarea programada');
    await _sincronizarCache();
    await _liberarExpiradosLocalmente();
    debugPrint('✅ [Background] Tarea completada');
  }

  /// Actualiza la notificación con cuenta regresiva en tiempo real.
  /// Se ejecuta cada segundo. OBTIENE LOS DATOS DIRECTAMENTE DEL
  /// SERVIDOR para garantizar que siempre muestre información real
  /// y nunca tarjetas que ya fueron liberadas.
  ///
  /// Selecciona la tarjeta con menor tiempo restante (la más próxima
  /// a expirar). Si alguien registra una nueva con menos tiempo, la
  /// notificación cambia inmediatamente.
  /// Solo se muestra UNA notificación en todo momento.
  static Future<void> _actualizarNotificacion() async {
    try {
      final ahora = DateTime.now();

      // --- Obtener datos REALES desde el servidor ---
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      List<Estacionamiento> estacionesServidor = [];
      List<Estacionamiento_Tarjeta> tarjetasServidor = [];

      if (token.isNotEmpty) {
        try {
          final results = await Future.wait([
            fetchEstacionamientos(
              token: token,
            ).timeout(const Duration(seconds: 10)),
            fetchEstacionamientoTarjeta(
              token: token,
            ).timeout(const Duration(seconds: 10)),
          ]);
          estacionesServidor = results[0] as List<Estacionamiento>;
          tarjetasServidor = (results[1] as List<Estacionamiento_Tarjeta>)
              .where((t) => t.estacionId > 0)
              .toList();
        } catch (_) {
          // Si falla la red, usar caché como fallback
        }
      }

      // Fallback a caché si no se pudo obtener del servidor
      if (estacionesServidor.isEmpty) {
        final estJson = prefs.getString('estacionamientos');
        if (estJson != null && estJson.isNotEmpty) {
          final List<dynamic> estData = json.decode(estJson);
          estacionesServidor = estData
              .map((e) => Estacionamiento.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
      if (tarjetasServidor.isEmpty) {
        final jsonString = prefs.getString('estacionamientos_tarjeta');
        if (jsonString != null && jsonString.isNotEmpty) {
          final List<dynamic> jsonData = json.decode(jsonString);
          tarjetasServidor = jsonData
              .map(
                (item) => Estacionamiento_Tarjeta.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .where((t) => t.estacionId > 0)
              .toList();
        }
      }

      // --- Construir set de estaciones realmente ocupadas ---
      final Set<int> estacionesOcupadas = {};
      for (final est in estacionesServidor) {
        if (est.estado == true) {
          estacionesOcupadas.add(est.id);
        }
      }

      if (tarjetasServidor.isEmpty) {
        if (_ultimaTarjeta != null) {
          _ultimaTarjeta = null;
          _ultimosMinutos = 0;
          _ultimosSegundos = 0;
          _ultimoUsuario = '';
        }
        await _mostrarNotificacion(
          titulo: 'SIMERT Estacionamientos',
          contenido: 'Sin estacionamientos activos',
        );
        return;
      }

      final hoyStr = DateFormat('yyyy-MM-dd').format(ahora);

      // --- Calcular segundos restantes para cada tarjeta ---
      Estacionamiento_Tarjeta? mejorTarjeta;
      int? mejorSegundos;

      for (final t in tarjetasServidor) {
        if (t.estacionId <= 0) continue;
        // Solo tarjetas del día de hoy
        if (t.fecha != hoyStr) continue;
        // Solo si la estación está realmente ocupada en el servidor
        if (!estacionesOcupadas.contains(t.estacionId)) continue;

        final segundos = _segundosRestantes(t, ahora);
        if (segundos == null || segundos <= 0) continue;

        if (mejorSegundos == null || segundos < mejorSegundos) {
          mejorSegundos = segundos;
          mejorTarjeta = t;
        }
      }

      // --- Mostrar la tarjeta con menor tiempo restante ---
      if (mejorTarjeta == null || mejorSegundos == null) {
        if (_ultimaTarjeta != null) {
          _ultimaTarjeta = null;
          _ultimosMinutos = 0;
          _ultimosSegundos = 0;
          _ultimoUsuario = '';
        }
        await _mostrarNotificacion(
          titulo: 'SIMERT Estacionamientos',
          contenido: 'Sin estacionamientos activos',
        );
        return;
      }

      // Si la mejor tarjeta cambió, actualizar datos
      final bool cambioTarjeta =
          _ultimaTarjeta?.estacionId != mejorTarjeta.estacionId;
      _ultimaTarjeta = mejorTarjeta;
      _ultimosMinutos = mejorSegundos ~/ 60;
      _ultimosSegundos = mejorSegundos % 60;
      if (cambioTarjeta) {
        _ultimoUsuario = await _obtenerNombreUsuario(mejorTarjeta.usuario);
      }

      final tiempo =
          '${_ultimosMinutos.toString().padLeft(2, '0')}:${_ultimosSegundos.toString().padLeft(2, '0')}';
      await _mostrarNotificacion(
        titulo: '#${mejorTarjeta.estacionId} - ${mejorTarjeta.placa}',
        contenido: '⏱ $tiempo restante | 👤 $_ultimoUsuario',
      );
    } catch (e) {
      debugPrint('❌ Error actualizando notificación: $e');
    }
  }

  /// Verifica que la tarjeta actual (_ultimaTarjeta) siga existiendo
  /// en el caché de tarjetas y que su estación esté ocupada.
  static bool _verificarTarjetaSigueActiva(SharedPreferences prefs) {
    try {
      final estJson = prefs.getString('estacionamientos');
      if (estJson != null && estJson.isNotEmpty) {
        final List<dynamic> estData = json.decode(estJson);
        for (final est in estData) {
          if (est['id'] == _ultimaTarjeta!.estacionId) {
            return est['estado'] == true;
          }
        }
        return false; // La estación ya no existe
      }
    } catch (_) {}
    return true; // Si no podemos verificar, asumir que sigue activa
  }

  /// Recarga los datos de la notificación desde SharedPreferences
  static Future<void> _recargarDatosNotificacion() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final jsonString = prefs.getString('estacionamientos_tarjeta');
      if (jsonString == null || jsonString.isEmpty) {
        _ultimaTarjeta = null;
        _ultimosMinutos = 0;
        _ultimosSegundos = 0;
        _ultimoUsuario = '';
        await _mostrarNotificacion(
          titulo: 'SIMERT Estacionamientos',
          contenido: 'Sin estacionamientos activos',
        );
        return;
      }

      final List<dynamic> jsonData = json.decode(jsonString);
      final List<Estacionamiento_Tarjeta> tarjetas = jsonData
          .map(
            (item) =>
                Estacionamiento_Tarjeta.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      if (tarjetas.isEmpty) {
        _ultimaTarjeta = null;
        _ultimosMinutos = 0;
        _ultimosSegundos = 0;
        _ultimoUsuario = '';
        await _mostrarNotificacion(
          titulo: 'SIMERT Estacionamientos',
          contenido: 'Sin estacionamientos activos',
        );
        return;
      }

      // --- Cargar estacionamientos para filtrar solo los que están ocupados ---
      final Set<int> estacionesOcupadas = {};
      try {
        final estJson = prefs.getString('estacionamientos');
        if (estJson != null && estJson.isNotEmpty) {
          final List<dynamic> estData = json.decode(estJson);
          for (final est in estData) {
            if (est['estado'] == true) {
              final id = est['id'] as int?;
              if (id != null && id > 0) estacionesOcupadas.add(id);
            }
          }
        }
      } catch (_) {}
      // --------------------------------------------------------------------

      final ahora = DateTime.now();
      final List<Map<String, dynamic>> conTiempo = [];

      final hoyStr = DateFormat('yyyy-MM-dd').format(ahora);

      for (final t in tarjetas) {
        if (t.estacionId <= 0) continue;
        try {
          // SOLO mostrar tarjetas cuya estación esté realmente ocupada
          if (!estacionesOcupadas.contains(t.estacionId)) continue;
          // SOLO mostrar tarjetas del día de hoy
          if (t.fecha != hoyStr) continue;

          final totalSegundos = _segundosRestantes(t, ahora);
          if (totalSegundos == null) continue;
          if (totalSegundos > 0) {
            conTiempo.add({
              'tarjeta': t,
              'segundos': totalSegundos,
              'hora': t.horaSalida,
            });
          }
        } catch (_) {}
      }

      if (conTiempo.isEmpty) {
        _ultimaTarjeta = null;
        _ultimosMinutos = 0;
        _ultimosSegundos = 0;
        _ultimoUsuario = '';
        await _mostrarNotificacion(
          titulo: 'SIMERT Estacionamientos',
          contenido: 'Sin estacionamientos activos',
        );
      } else {
        conTiempo.sort((a, b) => a['segundos'].compareTo(b['segundos']));
        final p = conTiempo.first;
        final t = p['tarjeta'] as Estacionamiento_Tarjeta;
        final totalSegundos = p['segundos'] as int;

        _ultimaTarjeta = t;
        _ultimosMinutos = totalSegundos ~/ 60;
        _ultimosSegundos = totalSegundos % 60;
        // Obtener nombre del usuario: primero del modelo (viene del servidor),
        // si no, desde SharedPreferences
        _ultimoUsuario = t.usuarioNombre.isNotEmpty
            ? t.usuarioNombre
            : await _obtenerNombreUsuario(t.usuario);

        final tiempo =
            '${_ultimosMinutos.toString().padLeft(2, '0')}:${_ultimosSegundos.toString().padLeft(2, '0')}';
        await _mostrarNotificacion(
          titulo: '#${t.estacionId} - ${t.placa}',
          contenido: '⏱ $tiempo restante | 👤 $_ultimoUsuario',
        );
      }
    } catch (e) {
      debugPrint('❌ Error recargando datos: $e');
    }
  }

  /// Obtiene el nombre del usuario desde SharedPreferences.
  /// Busca en los datos de usuarios guardados localmente.
  /// Si no encuentra, devuelve "Usuario".
  static Future<String> _obtenerNombreUsuario(int usuarioId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Verificar si es el usuario actual
      final currentUserId = prefs.getInt('id') ?? 0;
      if (usuarioId == currentUserId) {
        final name = prefs.getString('name');
        if (name != null && name.isNotEmpty) return name;
      }

      // 2. Buscar en el mapa de usuarios guardado al sincronizar caché
      final mapaJson = prefs.getString('mapa_usuarios');
      if (mapaJson != null) {
        try {
          final decoded = json.decode(mapaJson) as Map<String, dynamic>;
          final nombre = decoded[usuarioId.toString()] as String?;
          if (nombre != null && nombre.isNotEmpty && nombre != 'Usuario') {
            return nombre;
          }
        } catch (_) {}
      }

      // 3. Buscar en datos de usuarios guardados (lista de usuarios)
      final usuariosJson = prefs.getString('usuarios');
      if (usuariosJson != null) {
        final List<dynamic> usuarios = json.decode(usuariosJson);
        for (final u in usuarios) {
          if (u['id'] == usuarioId) {
            final name = u['name'] as String?;
            if (name != null && name.isNotEmpty) return name;
            final username = u['username'] as String?;
            if (username != null && username.isNotEmpty) return username;
          }
        }
      }

      // 4. Buscar en datos de personas registradas
      final personasJson = prefs.getString('personas');
      if (personasJson != null) {
        final List<dynamic> personas = json.decode(personasJson);
        for (final p in personas) {
          if (p['usuario'] == usuarioId) {
            final name = p['nombre'] as String?;
            if (name != null && name.isNotEmpty) return name;
          }
        }
      }

      // 5. Si no se encontró, devolver solo "Usuario" sin número
      return 'Usuario';
    } catch (_) {
      return 'Usuario';
    }
  }

  /// Calcula segundos restantes de una tarjeta.
  /// Usa el mismo algoritmo de parseo que _CountdownTicker en la UI
  /// para garantizar que ambos muestren el mismo tiempo restante.
  static int? _segundosRestantes(Estacionamiento_Tarjeta t, DateTime ahora) {
    try {
      DateTime? salida;

      // Soporta datetime completo (ISO) enviado por backend.
      if (t.horaSalida.contains('T') || t.horaSalida.contains('-')) {
        final parsed = DateTime.tryParse(t.horaSalida);
        if (parsed != null) salida = parsed.toLocal();
      }

      // Si no tenemos fecha completa, parsear solo hora (HH:mm o HH:mm:ss)
      if (salida == null) {
        final parts = t.horaSalida.split(':');
        if (parts.length >= 2) {
          final hh = int.tryParse(parts[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
          final mm = int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0;
          final ss = parts.length >= 3
              ? (int.tryParse(parts[2].replaceAll(RegExp(r'\D'), '')) ?? 0)
              : 0;
          DateTime baseDate;
          try {
            baseDate = DateFormat('yyyy-MM-dd').parse(t.fecha);
          } catch (_) {
            baseDate = ahora;
          }
          salida = DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            hh,
            mm,
            ss,
          );
        }
      }

      if (salida == null) return null;

      final diff = salida.difference(ahora);
      if (diff.inSeconds <= 0) return 0;
      return diff.inSeconds;
    } catch (_) {
      return null;
    }
  }

  /// Fecha de hoy en formato yyyy-MM-dd para filtrar tarjetas vigentes.
  static String get _hoyStr => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Sincroniza el caché local con el servidor.
  /// Filtra las tarjetas para guardar SOLO las del día de hoy y no expiradas.
  static Future<void> _sincronizarCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      if (token.isEmpty) return;

      final estaciones = await fetchEstacionamientos(
        token: token,
      ).timeout(const Duration(seconds: 15));
      final tarjetas = await fetchEstacionamientoTarjeta(
        token: token,
      ).timeout(const Duration(seconds: 15));

      final ahora = DateTime.now();
      final hoyStr = _hoyStr;

      // Filtrar tarjetas: solo del día de hoy y no expiradas
      final tarjetasFiltradas = tarjetas.where((t) {
        if (t.estacionId <= 0) return false;
        if (t.fecha != hoyStr) return false;
        // Verificar no expirada por hora
        try {
          final entrada = DateFormat('HH:mm').parse(t.horaEntrada);
          final salida = DateFormat('HH:mm').parse(t.horaSalida);
          final salidaDt = DateTime(
            ahora.year,
            ahora.month,
            ahora.day,
            salida.hour,
            salida.minute,
          );
          final entradaDt = DateTime(
            ahora.year,
            ahora.month,
            ahora.day,
            entrada.hour,
            entrada.minute,
          );
          DateTime salidaReal = salidaDt;
          if (salidaDt.isBefore(entradaDt)) {
            salidaReal = salidaDt.add(const Duration(days: 1));
          }
          return salidaReal.isAfter(ahora);
        } catch (_) {
          return true; // si no se puede parsear, mantenerla
        }
      }).toList();

      // Guardar estaciones (sin filtro, es la fuente de verdad de estado)
      await prefs.setString(
        'estacionamientos',
        json.encode(estaciones.map((e) => e.toJson()).toList()),
      );
      // Guardar tarjetas SOLO del día de hoy y no expiradas
      await prefs.setString(
        'estacionamientos_tarjeta',
        json.encode(tarjetasFiltradas.map((t) => t.toJson()).toList()),
      );

      // Guardar mapa de usuario_id → nombre para mostrarlo en la notificación
      await _guardarNombresUsuarios(tarjetasFiltradas, prefs);

      debugPrint(
        '🔄 Caché sincronizado: ${estaciones.length} est, ${tarjetasFiltradas.length} tar (${tarjetas.length - tarjetasFiltradas.length} filtradas)',
      );
    } catch (e) {
      debugPrint('⚠️ Error sincronizando caché: $e');
    }
  }

  /// Guarda un mapa de usuario_id → nombre en SharedPreferences
  /// para poder mostrar el nombre del usuario que registró cada tarjeta.
  static Future<void> _guardarNombresUsuarios(
    List<Estacionamiento_Tarjeta> tarjetas,
    SharedPreferences prefs,
  ) async {
    try {
      final Map<int, String> mapaNombres = {};
      final mapaJson = prefs.getString('mapa_usuarios');
      if (mapaJson != null) {
        final decoded = json.decode(mapaJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          mapaNombres[int.parse(entry.key)] = entry.value as String;
        }
      }

      // Agregar el usuario actual si existe
      final currentId = prefs.getInt('id') ?? 0;
      final currentName = prefs.getString('name') ?? '';
      if (currentId > 0 && currentName.isNotEmpty) {
        mapaNombres[currentId] = currentName;
      }

      // Recopilar IDs de usuarios que no tenemos en el mapa
      final Set<int> idsFaltantes = {};
      for (final t in tarjetas) {
        if (t.usuario > 0) {
          // Si la tarjeta ya trae el nombre embebido, guardarlo directamente
          if (t.usuarioNombre.isNotEmpty) {
            mapaNombres[t.usuario] = t.usuarioNombre;
          } else if (!mapaNombres.containsKey(t.usuario)) {
            idsFaltantes.add(t.usuario);
          }
        }
      }

      // Intentar obtener nombres desde el servidor para los IDs faltantes
      if (idsFaltantes.isNotEmpty) {
        final token = prefs.getString('token') ?? '';
        if (token.isNotEmpty) {
          try {
            final uri = Uri.parse(
              'https://simert.transitoelguabo.gob.ec/api/usuarios/?_tk=${Uri.encodeComponent(token)}',
            );
            final resp = await HttpMonitorizado.get(
              uri,
            ).timeout(const Duration(seconds: 10));
            if (resp.statusCode == 200) {
              final List<dynamic> usuarios = json.decode(resp.body);
              for (final u in usuarios) {
                final id = u['id'] as int?;
                if (id != null && idsFaltantes.contains(id)) {
                  final name = u['name'] as String?;
                  if (name != null && name.isNotEmpty) {
                    mapaNombres[id] = name;
                  }
                }
              }
            }
          } catch (_) {
            debugPrint('⚠️ No se pudieron obtener nombres de usuarios');
          }
        }
      }

      // Los que aún faltan, ponerlos como 'Usuario'
      for (final id in idsFaltantes) {
        if (!mapaNombres.containsKey(id)) {
          mapaNombres[id] = 'Usuario';
        }
      }

      await prefs.setString('mapa_usuarios', json.encode(mapaNombres));
    } catch (_) {}
  }

  /// Libera localmente los estacionamientos cuyo tiempo haya expirado
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

      // Si la tarjeta que estábamos mostrando fue liberada, recargar datos
      if (_ultimaTarjeta != null &&
          idsLiberados.contains(_ultimaTarjeta!.estacionId)) {
        _ultimaTarjeta = null;
        _ultimosMinutos = 0;
        _ultimosSegundos = 0;
        _ultimoUsuario = '';
        await _recargarDatosNotificacion();
      }
    } catch (e) {
      debugPrint('❌ Error liberando expirados: $e');
    }
  }
}

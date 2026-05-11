import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'splash_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'core/constantes.dart';
import 'core/tema.dart';
import 'servicios/servicioNotificacionesBackground.dart';
import 'servicios/servicioMinimizar.dart';

/// Nombre único para la tarea periódica de WorkManager
const String _tareaBackground = 'com.simert.estacionamiento.liberar_expirados';

/// Callback global que WorkManager ejecuta incluso con la app cerrada.
/// Debe ser una función top-level o estática.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🔄 [WorkManager] Ejecutando tarea: $task');
    try {
      // Ejecutar liberación de expirados y sincronización
      await ServicioNotificacionesBackground.ejecutarTareaBackground();
      debugPrint('✅ [WorkManager] Tarea completada: $task');
      return Future.value(true);
    } catch (e) {
      debugPrint('❌ [WorkManager] Error en tarea $task: $e');
      return Future.value(false);
    }
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar WorkManager
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Configuración de borde a borde para Android 15+
  // Usar SystemUiMode.edgeToEdge en lugar de APIs obsoletas como setStatusBarColor
  // El EdgeToEdge.enable() nativo en MainActivity.kt maneja la parte nativa.
  // En Flutter, configuramos el modo edge-to-edge y delegamos el padding
  // de las barras del sistema al builder global (MediaQuery.removePadding + SafeArea).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MyApp());

  // Inicializar servicios después de runApp (sin await para no bloquear)
  unawaited(_iniciarServicios());
}

Future<void> _iniciarServicios() async {
  try {
    // Solicitar permisos primero
    await _solicitarPermisos();

    // Inicializar OneSignal
    await _initOneSignal();

    // Iniciar sincronización de caché y liberación de expirados
    await ServicioNotificacionesBackground.iniciarServicio();

    // Enviar token al servicio nativo si ya hay sesión iniciada
    unawaited(ServicioMinimizar.enviarTokenAlServicioNatvio());

    // Programar tarea periódica de WorkManager (mínimo 15 minutos en Android)
    await Workmanager().registerPeriodicTask(
      'liberar_expirados',
      _tareaBackground,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    debugPrint('🟢 [WorkManager] Tarea periódica registrada (cada 15 min)');
  } catch (e) {
    debugPrint('❌ Error iniciando servicios: $e');
  }
}

Future<void> _solicitarPermisos() async {
  try {
    // Permiso de notificaciones (Android 13+)
    if (defaultTargetPlatform == TargetPlatform.android) {
      final notifStatus = await Permission.notification.request();
      debugPrint(
        'Permiso notificaciones: ${notifStatus.isGranted ? "concedido" : "denegado"}',
      );
    }

    // Permiso de cámara
    final camStatus = await Permission.camera.request();
    debugPrint(
      'Permiso cámara: ${camStatus.isGranted ? "concedido" : "denegado"}',
    );

    // Permiso de almacenamiento
    final storageStatus = await Permission.storage.request();
    debugPrint(
      'Permiso almacenamiento: ${storageStatus.isGranted ? "concedido" : "denegado"}',
    );
  } catch (e) {
    debugPrint('⚠️ Error solicitando permisos: $e');
  }
}

Future<void> _initOneSignal() async {
  // OneSignal solo funciona en Android/iOS
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    debugPrint('[OneSignal] Plataforma no soportada — omitiendo');
    return;
  }
  try {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize("26291df8-34b8-4fe8-8b1a-511a4fa8b95b");
    final result = await OneSignal.Notifications.requestPermission(true);
    debugPrint('[OneSignal] Inicializado. Permiso: $result');
  } catch (e) {
    debugPrint('[OneSignal] Error al inicializar: $e');
  }
}

/// GlobalKey del navigator para navegar desde servicios sin contexto
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'SIMERT Login',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'EC'),
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],
      theme: AppTema.claro,
      darkTheme: AppTema.oscuro,
      themeMode: ThemeMode.system,
      builder: (context, child) => _AdaptadorResponsiveGlobal(child: child),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      home: const SplashScreen(),
    );
  }
}

class _AdaptadorResponsiveGlobal extends StatelessWidget {
  const _AdaptadorResponsiveGlobal({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (child == null) return const SizedBox.shrink();

    // PopScope global: intercepta el botón de retroceso en Android para
    // minimizar la app en lugar de cerrarla, manteniendo el WebSocket y
    // el polling activos en segundo plano y la caché siempre actualizada.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ServicioMinimizar.minimizar();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final clampedTextScaler = media.textScaler.clamp(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.2,
          );

          // En modo edge-to-edge (Android 15+), el contenido se renderiza
          // detrás de las barras del sistema. SafeArea en cada pantalla se
          // encarga de aplicar el padding correcto. Aquí solo ajustamos
          // opcionalmente el textScaler.
          Widget contenido = MediaQuery(
            data: media.copyWith(textScaler: clampedTextScaler),
            child: child!,
          );

          if (constraints.maxWidth <= Responsive.quiebreTablet) {
            return contenido;
          }

          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Responsive.anchoMaxContenido,
                ),
                child: contenido,
              ),
            ),
          );
        },
      ),
    );
  }
}

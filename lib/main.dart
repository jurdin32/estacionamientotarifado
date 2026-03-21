import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'splash_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _initOneSignal();
  runApp(const MyApp());
  requestCameraPermission();
  requestStoragePermission();
}

void _initOneSignal() {
  // OneSignal solo funciona en Android/iOS
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    debugPrint('[OneSignal] Plataforma no soportada — omitiendo');
    return;
  }
  try {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize("26291df8-34b8-4fe8-8b1a-511a4fa8b95b");
    OneSignal.Notifications.requestPermission(true);
  } catch (e) {
    debugPrint('[OneSignal] Error al inicializar: $e');
  }
}

// Para la cámara
Future<void> requestCameraPermission() async {
  final status = await Permission.camera.request();
  if (status.isGranted) {
    debugPrint('Permiso de cámara concedido');
  } else {
    debugPrint('Permiso de cámara denegado');
  }
}

// Para archivos (almacenamiento externo)
Future<void> requestStoragePermission() async {
  final status = await Permission.storage
      .request(); // o Permission.mediaLibrary en API 33+
  if (status.isGranted) {
    debugPrint('Permiso de almacenamiento concedido');
  } else {
    debugPrint('Permiso de almacenamiento denegado');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIMERT Login',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'splash_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  // Initialize with your OneSignal App ID
  OneSignal.initialize("26291df8-34b8-4fe8-8b1a-511a4fa8b95b");
  // Use this method to prompt for push notifications.
  // We recommend removing this method after testing and instead use In-App Messages to prompt for notification permission.
  OneSignal.Notifications.requestPermission(true);
  requestCameraPermission();
  requestStoragePermission();
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

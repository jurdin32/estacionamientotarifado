# Guía de Implementación - Impresora Bluetooth Térmica Mini

## 📋 Tabla de contenidos
1. [Requisitos previos](#requisitos-previos)
2. [Instalación de dependencias](#instalación-de-dependencias)
3. [Configuración de Android](#configuración-de-android)
4. [Configuración de iOS](#configuración-de-ios)
5. [Uso básico](#uso-básico)
6. [Ejemplos de integración](#ejemplos-de-integración)
7. [Solución de problemas](#solución-de-problemas)

---

## 🔧 Requisitos previos

- **Flutter:** v3.8.0 o superior
- **Android:** SDK 21+ (mejor con 23+)
- **iOS:** 11.0+
- **Impresora Bluetooth:**
  - Zjiang ZJ-58
  - Sunmi
  - Xprinter
  - Cualquier impresora térmica estándar ESC/POS

---

## 📦 Instalación de dependencias

Ya tienes `flutter_bluetooth_serial` instalado. Verifica en `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_bluetooth_serial: ^0.4.0
  permission_handler: ^12.0.1
```

Si no lo tienes, ejecuta:
```bash
flutter pub add flutter_bluetooth_serial
flutter pub add permission_handler
```

---

## 🤖 Configuración de Android

### 1. Actualizar `AndroidManifest.xml`

Abre `android/app/src/main/AndroidManifest.xml` y agrega:

```xml
<!-- Permisos para Bluetooth -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Característica Bluetooth -->
<uses-feature
    android:name="android.hardware.bluetooth"
    android:required="true" />
```

### 2. Configurar `build.gradle` (nivel de la app)

Verifica que esté en `android/app/build.gradle`:

```gradle
android {
    compileSdk 34
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

---

## 🍎 Configuración de iOS

### 1. Actualizar `Info.plist`

Abre `ios/Runner/Info.plist` y agrega:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Esta aplicación necesita acceso a Bluetooth para conectar con impresoras térmicas</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>Esta aplicación necesita acceso a Bluetooth para conectar con impresoras térmicas</string>

<key>NSLocalNetworkUsageDescription</key>
<string>Esta aplicación necesita acceso a la red local</string>

<key>NSBonjourServices</key>
<array>
    <string>_printer._tcp</string>
</array>
```

### 2. Actualizar `Podfile`

En `ios/Podfile`, asegúrate de que el target mínimo sea 11.0:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_LOCATION=1',
      ]
    end
  end
end
```

---

## 🚀 Uso básico

### Opción 1: Pantalla de control completa

```dart
import 'package:tu_app/tarjetas/views/ImpresoraBluetooth.dart';

Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => ImpresoraBluetooth()),
);
```

### Opción 2: Usar desde cualquier pantalla

```dart
import 'package:tu_app/servicios/gestorImpresora.dart';

final gestor = GestorImpresora();

// Imprimir una multa
bool resultado = await gestor.imprimirMultaConDialogo(
  context: context,
  placa: 'ABC-1234',
  tipoMulta: 'Estacionamiento Prohibido',
  valor: 50.00,
  fechaEmision: '10/12/2025 14:30',
  ubicacion: 'Calle Principal 123',
  numeroComprobante: 'CMP-2025-0001',
  observacion: 'Vehículo estacionado en zona prohibida',
  usuario: 'OPERADOR NOMBRE',
  idNotificacion: 1,
);

if (resultado) {
  print('Impresión exitosa');
} else {
  print('Impresión cancelada o falló');
}
```

### Opción 3: Widgets flotantes

```dart
import 'package:tu_app/tarjetas/views/WidgetsImpresora.dart';

Scaffold(
  floatingActionButton: FloatingImpresoraButton(
    onImpresora: () {
      GestorImpresora().mostrarConfiguracionImpresora(context);
    },
  ),
  body: Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IndicadorEstadoImpresora(),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () async {
            await mostrarDialogoConectarImpresora(context);
          },
          child: Text('Conectar Impresora'),
        ),
      ],
    ),
  ),
);
```

---

## 📚 Ejemplos de integración

### Ejemplo 1: Integración en pantalla de multas

```dart
import 'package:tu_app/servicios/gestorImpresora.dart';

class PantallaMultas extends StatelessWidget {
  final GestorImpresora _gestor = GestorImpresora();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Multas'),
        actions: [
          EstadoImpresoraCompacto(
            onPressed: () {
              _gestor.mostrarConfiguracionImpresora(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingImpresoraButton(
        onImpresora: () {
          _gestor.mostrarConfiguracionImpresora(context);
        },
      ),
      body: ListView(
        children: [
          // ... lista de multas
          ListTile(
            title: Text('ABC-1234'),
            subtitle: Text('Estacionamiento Prohibido'),
            onLongPress: () => _imprimirMulta(context),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimirMulta(BuildContext context) async {
    await _gestor.imprimirMultaConDialogo(
      context: context,
      placa: 'ABC-1234',
      tipoMulta: 'Estacionamiento Prohibido',
      valor: 50.00,
      fechaEmision: DateTime.now().toString(),
      ubicacion: 'Calle Principal 123',
      numeroComprobante: 'CMP-2025-0001',
      observacion: 'Vehículo estacionado en zona prohibida',
      usuario: 'OPERADOR',
      idNotificacion: 1,
    );
  }
}
```

### Ejemplo 2: Servicio directo

```dart
import 'package:tu_app/servicios/servicioImpresionTermica.dart';

class MiServicio {
  final _servicio = ServicioImpresionTermica();

  Future<void> procesarMulta(MultaData multa) async {
    // Verificar conexión
    if (!_servicio.estaConectado) {
      throw Exception('Impresora no conectada');
    }

    // Imprimir
    await _servicio.imprimirMulta(
      placa: multa.placa,
      tipoMulta: multa.tipo,
      valor: multa.monto,
      fechaEmision: multa.fecha,
      ubicacion: multa.ubicacion,
      numeroComprobante: multa.comprobante,
      observacion: multa.observacion,
      usuario: multa.usuarioOperador,
      idNotificacion: multa.id,
    );

    print('Multa impresa: ${multa.placa}');
  }
}
```

---

## 🔍 Solución de problemas

### Problema: "No se encuentra la impresora"

**Solución:**
1. Emparejar la impresora manualmente en Configuración > Bluetooth de Android
2. Asegúrate de que la impresora esté encendida
3. Reinicia la aplicación
4. Recarga la lista de dispositivos

### Problema: "Error de conexión"

**Solución:**
1. Verifica que la impresora esté dentro del rango Bluetooth (10 metros)
2. Comprueba los permisos en Configuración > Aplicaciones > tu_app
3. Asegúrate de que Bluetooth esté activado en el dispositivo
4. Intenta desemparejar y emparejar nuevamente

### Problema: "No imprime después de conectar"

**Solución:**
1. Verifica que la impresora tenga papel
2. Comprueba que la batería de la impresora no esté baja
3. Intenta un segundo comando de impresión (algunas impresoras necesitan inicialización)
4. Reinicia la impresora

### Problema: "Permisos denegados"

**Solución:**
```dart
// El código solicitará permisos automáticamente
bool permisosOk = await ServicioImpresionTermica().solicitarPermisos();

if (!permisosOk) {
  // Abre la configuración de la app
  openAppSettings();
}
```

### Problema: "Error ESC/POS"

**Solución:**
Algunas impresoras pueden requerir comandos específicos. Modifica los bytes en `servicioImpresionTermica.dart`:

```dart
// Para impresoras con puerto diferente
static final List<int> _init = [0x1B, 0x40]; // Prueba también [0x1B, 0x3D, 0x01]
```

---

## 🎨 Personalización

### Cambiar formato del ticket

En `servicioImpresionTermica.dart`, modifica el método `_generarTicketTermico()`:

```dart
// Cambiar alineación
bytes.addAll(_alinearCentro); // Centrado
bytes.addAll(_alinearIzquierda); // Izquierda
bytes.addAll(_alinearDerecha); // Derecha

// Cambiar tamaño
bytes.addAll(_tamanoNormal); // Tamaño normal
bytes.addAll(_tamanoDoble); // Tamaño doble

// Cambiar estilos
bytes.addAll(_negritaOn); // Negrita
bytes.addAll(_dobleAlturaOn); // Altura doble
```

### Agregar logo

```dart
// Aún no soportado por flutter_bluetooth_serial
// Pero puedes agregar más líneas de texto personalizadas
bytes.addAll(utf8.encode("╔════════════════════════╗\n"));
bytes.addAll(utf8.encode("║    TU LOGO AQUÍ        ║\n"));
bytes.addAll(utf8.encode("╚════════════════════════╝\n"));
```

---

## 📱 Características implementadas

✅ Escaneo de dispositivos Bluetooth  
✅ Emparejamiento y conexión  
✅ Impresión de tickets en formato ESC/POS  
✅ Control de alineación (izquierda, centro, derecha)  
✅ Estilos de texto (negrita, tamaño doble)  
✅ Corte de papel automático  
✅ Manejo de errores  
✅ Widgets reutilizables  
✅ Interfaz amigable  
✅ Soporte para múltiples tipos de impresoras  

---

## 🆘 Soporte

Si encuentras problemas:

1. Verifica los logs en Android Studio: `flutter logs`
2. Prueba con una app de prueba de Bluetooth
3. Consult el manual de tu impresora térmica
4. Verifica la versión de `flutter_bluetooth_serial`

---

**¡Listo!** Tu impresora Bluetooth térmica mini está completamente integrada. 🎉

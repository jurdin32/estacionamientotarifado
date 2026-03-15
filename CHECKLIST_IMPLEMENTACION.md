# ✅ Checklist de Implementación - Impresora Bluetooth

## 🎯 Fase 1: Preparación (5-10 minutos)

### Dependencias
- [ ] `flutter_bluetooth_serial: ^0.4.0` en pubspec.yaml
- [ ] `permission_handler: ^12.0.1` en pubspec.yaml
- [ ] Ejecuté `flutter pub get`
- [ ] No hay errores de dependencias

### Archivos descargados
- [ ] `ImpresoraBluetooth.dart` en `lib/tarjetas/views/`
- [ ] `WidgetsImpresora.dart` en `lib/tarjetas/views/`
- [ ] `gestorImpresora.dart` en `lib/servicios/`
- [ ] `pruebaImpresora.dart` en `lib/servicios/`
- [ ] `ejemplos_impresora.dart` en `lib/`
- [ ] Archivos de documentación (.md)

---

## 🤖 Fase 2: Configuración Android (10-15 minutos)

### AndroidManifest.xml
- [ ] Abrí `android/app/src/main/AndroidManifest.xml`
- [ ] Agregué permisos Bluetooth:
  ```xml
  <uses-permission android:name="android.permission.BLUETOOTH" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  ```
- [ ] Agregué característica Bluetooth:
  ```xml
  <uses-feature
      android:name="android.hardware.bluetooth"
      android:required="true" />
  ```

### build.gradle
- [ ] Verificué `minSdkVersion 21` en `android/app/build.gradle`
- [ ] Verificué `compileSdk 34` en `android/app/build.gradle`
- [ ] Ejecuté `flutter clean && flutter pub get`

---

## 🍎 Fase 3: Configuración iOS (5-10 minutos) - *Si aplica*

### Info.plist
- [ ] Abrí `ios/Runner/Info.plist`
- [ ] Agregué:
  ```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Esta aplicación necesita acceso a Bluetooth</string>
  ```
- [ ] Agregué:
  ```xml
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>Esta aplicación necesita acceso a Bluetooth</string>
  ```

### Podfile
- [ ] Verificué que iOS target es 11.0 o superior

---

## 🔧 Fase 4: Emparejamiento de hardware (5 minutos)

### En tu teléfono Android
- [ ] Abrí Configuración > Bluetooth
- [ ] Activé Bluetooth
- [ ] Busqué "Agregar dispositivo" o "Emparejar dispositivo"
- [ ] Encendí la impresora térmica
- [ ] Seleccioné la impresora de la lista (ZJ-58, Sunmi, Xprinter, etc.)
- [ ] Emparé correctamente
- [ ] La impresora aparece en "Dispositivos emparejados"

---

## 🧪 Fase 5: Primera prueba (10 minutos)

### Prueba básica en la app
- [ ] Ejecuté `flutter run`
- [ ] Navegué a la pantalla `ImpresoraBluetooth`
  ```dart
  Navigator.push(context, MaterialPageRoute(
    builder: (context) => ImpresoraBluetooth(),
  ));
  ```
- [ ] Presioné botón "Escanear" 
- [ ] Apareció mi impresora en la lista
- [ ] Presioné sobre la impresora para conectar
- [ ] Vio "CONECTADO" con nombre de la impresora
- [ ] Presioné "Imprimir Ticket de Prueba"
- [ ] **¡El ticket se imprimió! ✓**

### Si no funcionó:
- [ ] Revisé los logs: `flutter logs`
- [ ] Consulté el archivo `TROUBLESHOOTING_IMPRESORA.md`
- [ ] Deemparejar y emparejar nuevamente
- [ ] Reiniciar teléfono e impresora
- [ ] Verificar que Bluetooth está activado

---

## 📱 Fase 6: Integración en tus pantallas (15-30 minutos)

### Opción A: Agregar a pantalla existente (RECOMENDADO)

En tu `NotificacionScreen.dart` o donde quieras:

- [ ] Importé el gestor:
  ```dart
  import 'servicios/gestorImpresora.dart';
  import 'tarjetas/views/WidgetsImpresora.dart';
  ```

- [ ] Agregué indicador en AppBar:
  ```dart
  appBar: AppBar(
    title: Text('Mi Pantalla'),
    actions: [
      EstadoImpresoraCompacto(
        onPressed: () {
          GestorImpresora().mostrarConfiguracionImpresora(context);
        },
      ),
    ],
  ),
  ```

- [ ] Agregué botón flotante:
  ```dart
  floatingActionButton: FloatingImpresoraButton(
    onImpresora: () {
      GestorImpresora().mostrarConfiguracionImpresora(context);
    },
  ),
  ```

- [ ] Agregué método de impresión:
  ```dart
  Future<void> _imprimirMulta(BuildContext context) async {
    await GestorImpresora().imprimirMultaConDialogo(
      context: context,
      placa: 'ABC-1234',
      tipoMulta: 'Estacionamiento Prohibido',
      valor: 50.00,
      fechaEmision: DateTime.now().toString(),
      ubicacion: 'Calle Principal 123',
      numeroComprobante: 'CMP-2025-0001',
      observacion: 'Observación',
      usuario: 'OPERADOR',
      idNotificacion: 1,
    );
  }
  ```

- [ ] Agregué botón que llama el método:
  ```dart
  ElevatedButton.icon(
    onPressed: () => _imprimirMulta(context),
    icon: Icon(Icons.print),
    label: Text('Imprimir'),
  ),
  ```

### Opción B: Crear nueva ruta

- [ ] En `main.dart`, agregué ruta:
  ```dart
  routes: {
    '/impresora': (context) => ImpresoraBluetooth(),
  },
  ```

- [ ] Agregué botón que navega:
  ```dart
  ElevatedButton(
    onPressed: () {
      Navigator.pushNamed(context, '/impresora');
    },
    child: Text('Ir a Impresora'),
  ),
  ```

---

## 🧬 Fase 7: Pruebas de integración (10-15 minutos)

### En tu pantalla integrada
- [ ] Veo el indicador de estado en la AppBar
- [ ] El indicador muestra "Conectada" o "Desconectada" correctamente
- [ ] Presiono sobre el indicador y se abre configuración
- [ ] Presiono el botón flotante y se abre configuración
- [ ] Puedo conectar desde el diálogo
- [ ] El estado se actualiza después de conectar
- [ ] Presiono el botón "Imprimir"
- [ ] Aparece diálogo de confirmación
- [ ] Presiono "Imprimir" en el diálogo
- [ ] **¡El ticket se imprime! ✓**

### Si hay errores:
- [ ] Reviso los logs en `flutter logs`
- [ ] Consulto `TROUBLESHOOTING_IMPRESORA.md`
- [ ] Pruebo el ejemplo `NotificacionScreenEjemplo.dart` primero
- [ ] Verifico que los imports sean correctos

---

## 🎨 Fase 8: Personalización (OPCIONAL)

### Cambiar colores
- [ ] Edité `ImpresoraBluetooth.dart` si quiero cambiar colores
- [ ] Cambié `Colors.blue[800]` por el color que quiero

### Cambiar formato de ticket
- [ ] Edité `servicioImpresionTermica.dart`
- [ ] Modifiqué el método `_generarTicketTermico()`
- [ ] Agregué/removí líneas del ticket

### Agregar logo
- [ ] En `_generarTicketTermico()` agregué líneas decorativas:
  ```dart
  bytes.addAll(utf8.encode("╔════════════════════════╗\n"));
  bytes.addAll(utf8.encode("║      TU EMPRESA        ║\n"));
  bytes.addAll(utf8.encode("╚════════════════════════╝\n"));
  ```

---

## 🚀 Fase 9: Compilación y distribución (FINAL)

### Testing antes de release
- [ ] Probé en emulador (si tienes)
- [ ] Probé en dispositivo físico
- [ ] Probé con múltiples impresoras (si aplica)
- [ ] Probé imprimiendo múltiples tickets seguidos
- [ ] Probé desconectando y reconectando

### Build para release
- [ ] Ejecuté `flutter clean`
- [ ] Ejecuté `flutter pub get`
- [ ] Ejecuté `flutter build apk --release` (Android)
- [ ] Ejecuté `flutter build ios --release` (iOS) *si aplica*
- [ ] No hay errores en la compilación
- [ ] El APK/IPA se generó correctamente

### Documentación
- [ ] Documenté cómo conectar la impresora para el usuario final
- [ ] Incluí archivo `GUIA_IMPRESORA_BLUETOOTH.md` en la app
- [ ] Documenté pasos de troubleshooting para el usuario

---

## 📊 Resumen final

### Archivos modificados/creados
- [ ] `servicioImpresionTermica.dart` - ✓ Ya existía
- [ ] `gestorImpresora.dart` - ✓ Nuevo
- [ ] `ImpresoraBluetooth.dart` - ✓ Nuevo
- [ ] `WidgetsImpresora.dart` - ✓ Nuevo
- [ ] `NotificacionScreenEjemplo.dart` - ✓ Nuevo (referencia)
- [ ] `pruebaImpresora.dart` - ✓ Nuevo
- [ ] `ejemplos_impresora.dart` - ✓ Nuevo

### Documentación
- [ ] `GUIA_IMPRESORA_BLUETOOTH.md` - ✓ Creado
- [ ] `INTEGRACION_RAPIDA_MAIN.md` - ✓ Creado
- [ ] `TROUBLESHOOTING_IMPRESORA.md` - ✓ Creado
- [ ] `RESUMEN_ARCHIVOS_IMPRESORA.md` - ✓ Creado
- [ ] Este archivo (CHECKLIST) - ✓ Creado

---

## ✨ ¡COMPLETADO!

Si todos los puntos están marcados ✓, tu implementación está completa y funcionando.

### Próximos pasos:
1. Distribuir a tus usuarios
2. Proporciona la documentación de troubleshooting
3. Recibe feedback y mejora

### Soporte técnico:
- Consulta `TROUBLESHOOTING_IMPRESORA.md` para problemas comunes
- Revisa `GUIA_IMPRESORA_BLUETOOTH.md` para detalles técnicos
- Usa `PruebaImpresora` para debugging

---

**¡Tu aplicación de impresora Bluetooth está lista para producción! 🎉**

Fecha completación: ________________

Desarrollador: ________________

Versión: 1.0

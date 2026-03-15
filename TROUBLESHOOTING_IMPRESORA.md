# 🔧 Guía de Troubleshooting - Impresora Bluetooth

## Problema 1: "No aparece ningún dispositivo"

### Síntomas
- La lista de dispositivos está vacía
- O solo ve otros dispositivos pero no la impresora

### Soluciones

#### A. Verificar emparejamiento
```
1. Ve a Configuración > Bluetooth
2. Activa Bluetooth
3. Busca "Agregar dispositivo" o "Emparejar nuevo dispositivo"
4. Busca tu impresora (generalmente dice ZJ-58, Sunmi, etc.)
5. Selecciona y empareja
```

#### B. Reiniciar Bluetooth
```
1. Abre Configuración
2. Bluetooth > Desactiva
3. Espera 5 segundos
4. Activa nuevamente
```

#### C. Reiniciar impresora
```
1. Apaga la impresora
2. Espera 10 segundos
3. Enciende nuevamente
4. Abre la app nuevamente
```

#### D. Actualizar driver Bluetooth
```
1. Ve a Configuración > Sobre el teléfono
2. Toca "Versión de compilación" 7 veces
3. Activa "Opciones de desarrollador"
4. Abre Opciones de desarrollador
5. Busca opciones de Bluetooth y reinicia
```

#### E. Verificar permisos en Android 12+
```dart
// Agregar este código antes de escanear
bool ok = await GestorImpresora().solicitarPermisos();
if (!ok) {
  print('Permisos denegados');
  // Abre configuración de la app
  openAppSettings();
}
```

---

## Problema 2: "Error de conexión" o "Conexión rechazada"

### Síntomas
- Ves la impresora pero no se puede conectar
- Aparece mensaje "Connection failed"
- Desconexión inmediata después de conectar

### Soluciones

#### A. Verificar rango Bluetooth
```
- Acerca el teléfono a menos de 10 metros de la impresora
- Elimina obstáculos físicos entre los dispositivos
- Evita otras ondas de radio (WiFi, microondas)
```

#### B. Limpiar caché de conexiones
```
1. Ve a Configuración > Aplicaciones
2. Busca "Bluetooth" o "Configuración de Bluetooth"
3. Almacenamiento > Borrar caché
4. Reinicia el teléfono
```

#### C. Desemparejar y emparejar nuevamente
```
1. Configuración > Bluetooth
2. Toca tu impresora > Olvidar/Desemparejar
3. Espera 10 segundos
4. Busca nuevamente e empareja
```

#### D. Aumentar timeout en el código
```dart
// En servicioImpresionTermica.dart
// Busca esta línea:
_connection = await BluetoothConnection.toAddress(dispositivo.address)
    .timeout(Duration(seconds: 10));

// Cambia a:
_connection = await BluetoothConnection.toAddress(dispositivo.address)
    .timeout(Duration(seconds: 20)); // Espera más tiempo
```

#### E. Verificar que Bluetooth está habilitado en la app
```dart
bool isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
if (!isEnabled) {
  // Pedir que lo habilite
  await FlutterBluetoothSerial.instance.requestEnable();
}
```

---

## Problema 3: "Conecta pero no imprime nada"

### Síntomas
- La impresora muestra que está conectada
- Pero no sale ningún ticket
- O solo sale papel en blanco

### Soluciones

#### A. Verificar papel
```
1. Abre la tapa trasera de la impresora
2. Verifica que haya papel
3. Si no hay, carga papel nuevamente
4. Cierra la tapa hasta que haga clic
```

#### B. Limpiar cabezal térmico
```
1. Apaga la impresora
2. Toma un algodón ligeramente húmedo
3. Limpia suavemente el cabezal negro
4. Espera a que seque
5. Enciende nuevamente
```

#### C. Probar con comando simple
```dart
// En pruebaImpresora.dart, ejecuta:
await PruebaImpresora.pruebaSencilla();

// O directamente en debug:
final servicio = ServicioImpresionTermica();
if (servicio.estaConectado) {
  await servicio.imprimirMulta(
    placa: 'TEST',
    tipoMulta: 'Test',
    valor: 0.0,
    fechaEmision: 'TEST',
    ubicacion: 'TEST',
    numeroComprobante: 'TEST',
    observacion: 'TEST',
    usuario: 'TEST',
    idNotificacion: 0,
  );
}
```

#### D. Revisar tinta/cabezal
```
- Algunos modelos necesitan "activarse" después de cambiar papel
- Algunos modelos tienen un botón de "cleaning" (limpieza)
- Consulta el manual de tu impresora específica
```

#### E. Aumentar pausa entre fragmentos
```dart
// En servicioImpresionTermica.dart
// Busca esta línea en _enviarABluetooth:
await Future.delayed(Duration(milliseconds: 30));

// Cambia a:
await Future.delayed(Duration(milliseconds: 100)); // Pausa más larga
```

---

## Problema 4: "Impresión entrecortada o con caracteres raros"

### Síntomas
- El ticket imprime pero falta contenido
- Hay caracteres extraños o garrabatos
- Algunos renglones están en blanco

### Soluciones

#### A. Ajustar velocidad de envío
```dart
// En servicioImpresionTermica.dart, método _enviarABluetooth:
const int chunkSize = 256; // Prueba valores más pequeños
// Cambia a:
const int chunkSize = 128; // Fragmentos más pequeños

// Y aumenta la pausa:
await Future.delayed(Duration(milliseconds: 100));
```

#### B. Verificar encoding
```dart
// Asegúrate que los caracteres especiales se envíen como UTF-8
bytes.addAll(utf8.encode("texto"));
// Esto ya lo hacemos, pero verifica que funcione con tildes
```

#### C. Probar con imprimir sólo texto
```dart
// Simplifica el ticket a solo texto para probar:
List<int> bytes = [];
bytes.addAll(_init);
bytes.addAll(utf8.encode("PRUEBA\n"));
bytes.addAll(utf8.encode("Línea 2\n"));
bytes.addAll(_avanzarLinea);
bytes.addAll(utf8.encode("FIN\n"));

await _enviarABluetooth(bytes);
```

---

## Problema 5: "Permisos denegados"

### Síntomas
- "Permiso denegado" al intentar conectar
- No puede acceder a Bluetooth
- "Location permission required"

### Soluciones

#### A. Solicitar permisos manualmente
```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> solicitarPermisos() async {
  // Android 6.0+
  await Permission.location.request();
  
  // Android 12+
  await Permission.bluetoothConnect.request();
  await Permission.bluetoothScan.request();
}
```

#### B. Verificar en Configuración
```
1. Ve a Configuración > Aplicaciones > tu_app
2. Permisos > Bluetooth > Permitir
3. Permisos > Ubicación > Permitir mientras usa la app
```

#### C. Borrar datos de la app
```
1. Configuración > Aplicaciones > tu_app
2. Almacenamiento > Borrar datos
3. Vuelve a instalar la app
```

---

## Problema 6: "La conexión se corta constantemente"

### Síntomas
- Se conecta pero se desconecta después de unos segundos
- Aparece "Connection lost" frecuentemente
- Necesita reconectar para cada impresión

### Soluciones

#### A. Revisar interferencia de radio
```
- Aleja la impresora de WiFi routers
- Apaga el WiFi mientras usas Bluetooth
- Aleja de hornos microondas
```

#### B. Aumentar tiempo de conexión
```dart
// En servicioImpresionTermica.dart
_connection = await BluetoothConnection.toAddress(dispositivo.address)
    .timeout(Duration(seconds: 20));
```

#### C. Verificar batería de la impresora
```
- Algunas impresoras desconectan si la batería está baja
- Carga la batería completamente
- Prueba con corriente AC si tu impresora lo permite
```

#### D. Mantener conexión abierta
```dart
// Modifica el servicio para no cerrar después de cada impresión
// En lugar de:
await desconectar();

// Mantenla abierta:
// No llames a desconectar() después de cada impresión
```

---

## Problema 7: "Error: Input/Output Error"

### Síntomas
- Error "I/O error" o "Pipe broken"
- Ocurre durante la impresión
- La impresora se desconecta abruptamente

### Soluciones

#### A. Reducir tamaño de fragmentos
```dart
// En servicioImpresionTermica.dart, _enviarABluetooth:
const int chunkSize = 64; // Muy pequeño para debug
```

#### B. Agregar manejo de errores
```dart
try {
  _connection!.output.add(chunk);
  await _connection!.output.allSent;
} catch (e) {
  print('Error enviando: $e');
  // Reconectar
  await desconectar();
  rethrow;
}
```

#### C. Limpiar buffer antes de enviar
```dart
// Envía un comando de reset antes de cada impresión
bytes.addAll(_init); // Reinicializa la impresora
```

---

## Problema 8: "Android 12+ no ve dispositivos"

### Síntomas
- Android 12 o superior
- Lista vacía de dispositivos
- Funcionaba en versiones anteriores

### Soluciones

#### A. Agregar permisos en AndroidManifest.xml
```xml
<!-- Asegúrate que este archivo tenga: -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- En tiempo de ejecución, solicita: -->
```

#### B. Código para Android 12+
```dart
Future<bool> solicitarPermisosAndroid12() async {
  final status1 = await Permission.bluetoothConnect.request();
  final status2 = await Permission.bluetoothScan.request();
  final status3 = await Permission.location.request();
  
  return status1.isGranted && status2.isGranted && status3.isGranted;
}
```

#### C. Limpiar cache de Bluetooth
```
1. Configuración > Aplicaciones > Mostrar aplicaciones del sistema
2. Busca "Bluetooth"
3. Almacenamiento > Borrar caché
4. Reinicia el teléfono
```

---

## Problema 9: "Impresora muy lenta"

### Síntomas
- Tarda mucho tiempo en imprimir
- Algunos tickets tardan minutos
- Parece que se congela

### Soluciones

#### A. Aumentar velocidad de envío
```dart
// Reduce las pausas
await Future.delayed(Duration(milliseconds: 10)); // Era 30
```

#### B. Enviar sin fragmentación
```dart
// Si es un ticket pequeño, envía todo de una vez
_connection!.output.add(Uint8List.fromList(bytes));
await _connection!.output.allSent;
```

#### C. Verificar batería de la impresora
```
- Batería baja = procesamiento lento
- Carga completamente
```

---

## Problema 10: "Caracteres UTF-8 no salen correctamente"

### Síntomas
- Las tildes (á, é, í, ó, ú) no salen bien
- Caracteres especiales (ñ, ü) aparecen como garrabatos
- Otros idiomas no se imprimen correctamente

### Soluciones

#### A. Verificar encoding
```dart
// Asegúrate que uses utf8.encode:
bytes.addAll(utf8.encode("Calle Principal"));

// NO uses toString()
```

#### B. Si la impresora no soporta UTF-8
```dart
// Algunas impresoras antiguas usan CP437 o CP850
// Instala: flutter pub add charset

// O reemplaza caracteres:
String sanitizar(String texto) {
  return texto
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');
}
```

---

## 🔍 Diagnóstico rápido

Ejecuta esto para saber el estado:

```dart
import 'lib/servicios/pruebaImpresora.dart';

// En tu pantalla de debug:
@override
void initState() {
  super.initState();
  PruebaImpresora.pruebaCompleta(); // Imprime todo en logs
}
```

Revisa los logs en:
```
Android Studio > Logcat
O en terminal: flutter logs
```

---

## 📋 Checklist antes de reportar problema

- [ ] ¿Empáreja correctamente en Configuración > Bluetooth?
- [ ] ¿El teléfono tiene Bluetooth activado?
- [ ] ¿La impresora está encendida?
- [ ] ¿Hay papel en la impresora?
- [ ] ¿Los permisos están concedidos?
- [ ] ¿Prueba desde la pantalla ImpresoraBluetooth?
- [ ] ¿Otros apps de Bluetooth funcionan?
- [ ] ¿Probaste reiniciar impresora y teléfono?

---

**¡Si nada funciona, documenta el error exacto y nosotros te ayudamos!** 🤝

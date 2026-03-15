# Estacionamiento Tarifado — SIMERT

Aplicación móvil Flutter para la gestión de estacionamiento tarifado del **Municipio de El Guabo**. Se conecta al backend SIMERT (`simert.transitoelguabo.gob.ec`) y ofrece:

- Login de operadores y administradores.
- Registro y gestión de tarjetas de estacionamiento.
- Control de estaciones y multas.
- Notificaciones push via **OneSignal**.
- Impresión de tickets por Bluetooth (ESC/POS).

## Requisitos previos

| Herramienta | Versión mínima |
|-------------|----------------|
| Flutter     | 3.x (Dart ^3.8.1) |
| Android SDK | API 21+ |

## Configuración antes de compilar

### 1. Credenciales OneSignal

Copia el archivo de ejemplo y rellena con tus datos:

```bash
cp ONESIGNAL.example.txt ONESIGNAL.txt
```

Luego edita `lib/main.dart` y reemplaza el App ID de OneSignal:

```dart
OneSignal.initialize("<TU_APP_ID_DE_ONESIGNAL>");
```

### 2. Firebase Admin SDK (solo backend)

El archivo `*firebase-adminsdk*.json` **nunca se sube al repositorio**.
Si el proyecto lo requiere para tareas de administración, colócalo en la raíz del proyecto de forma local.

### 3. Firma Android (release)

Crea `android/key.properties` (excluido del repo) con:

```properties
storePassword=<contraseña>
keyPassword=<contraseña>
keyAlias=<alias>
storeFile=<ruta/al/keystore.jks>
```

## Instalación

```bash
flutter pub get
flutter run
```

## Build release (APK / AAB)

```bash
flutter build apk --release
# o
flutter build appbundle --release
```

También existe el script `build_release.ps1` para automatizar el proceso.

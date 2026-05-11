# Checklist de Publicacion - Google Play (Tarifado)

Fecha de referencia: 5 de agosto de 2026

## 1) Antes de compilar

- [x] Actualizar version en pubspec.yaml (version: 1.0.3+14).
- [x] Confirmar que el numero despues de + aumento (versionCode unico: +14).
- [x] Confirmar que la firma release usa la upload key correcta en android/key.properties.
- [x] Fijar minSdk = 23 (Android 6.0) para compatibilidad con version +14.
- [x] **AAB compilado**: `build/app/outputs/bundle/release/app-release.aab` (51.7 MB)
- [x] **Firma verificada**: SHA1 `86:18:D6:F8:E6:F1:10:B4:A9:A8:BE:F0:85:D8:8E:8E:C8:18:64:84` ✓

## 2) Compilar AAB ✅ COMPLETADO

Comando ejecutado:

```
flutter build appbundle --release
```

Salida:

```
√ Built build\app\outputs\bundle\release\app-release.aab (51.7MB)
```

## 3) Subir en Play Console (PENDIENTE - lo haces manualmente)

- [ ] Ir a Produccion -> Crear version nueva.
- [ ] Subir `build/app/outputs/bundle/release/app-release.aab`.
- [ ] Pegar notas de version (texto corto).
- [ ] Guardar cambios.
- [ ] Revisar alertas/errores en Resumen de publicacion.
- [ ] Enviar cambios para revision.

## 4) Verificaciones rapidas si falla

- Error "Version code already used": subir el +N en pubspec.yaml.
- Error de certificado/firma: revisar keystore y android/key.properties.
- Error "Release notes too long": reducir texto a 3-5 lineas.
- Bloqueo por politicas: completar formularios pendientes (seguridad de datos, permisos, etc.).

## 5) Plantilla corta para notas de version

```
Mejoras de rendimiento y estabilidad general.
Sincronizacion de datos optimizada.
Correcciones en registros, consultas y permisos por rol.
Interfaz mas clara y consistente en movil, tablet y escritorio.
```

## 6) Datos de firma validados en este proyecto

- SHA1 upload key valida para esta app: 86:18:D6:F8:E6:F1:10:B4:A9:A8:BE:F0:85:D8:8E:8E:C8:18:64:84
- Archivo keystore en proyecto: android/upload-keystore-prod.jks
- Archivo de configuracion: android/key.properties
- storeFile usado: ../upload-keystore-prod.jks
- keyAlias: upload
- Certificado valido: 2026 - 2053

## 7) Configuracion Play Store (+14)

Antes de publicar, asegurar en Play Console:

- [ ] **Clasificacion de contenido**: Responder cuestionario de clasificacion. Esta app es HERRAMIENTA (estacionamiento municipal) -> clasificacion minima.
- [ ] **Politica de privacidad**: Se requiere URL de politica de privacidad. Si no tienes, crear una en https://app.privacypolicies.com/ o similar.
- [ ] **Declaracion de permisos**: Revisar que usas:
  - INTERNET, NETWORK_STATE (red)
  - CAMARA (fotos de vehiculos)
  - BLUETOOTH, BLUETOOTH_CONNECT, BLUETOOTH_SCAN (impresora termica)
  - ACCESS_FINE_LOCATION (necesario para BLUETOOTH_SCAN en Android 12+)
  - POST_NOTIFICATIONS (notificaciones push)
  - FOREGROUND_SERVICE (servicio de notificacion con cuenta regresiva)
- [ ] **Target API**: targetSdk = 35 (Android 15) - OK
- [ ] **Formulario de Datos de Seguridad**: Completar en Play Console indicando que se recopilan datos de cuenta (login) y fotos (solo con consentimiento).
- [ ] **minSdk = 23** (Android 6.0) - OK, configurado

## Resumen de cambios realizados

| Archivo | Cambio |
|---------|--------|
| `pubspec.yaml` | version: `1.0.3+13` → `1.0.3+14` |
| `android/app/build.gradle.kts` | minSdk: `flutter.minSdkVersion` → `23` |
| `CHECKLIST_PUBLICACION_PLAY.md` | Actualizada con pasos completados |
| `build/app/outputs/bundle/release/app-release.aab` | ✅ Compilado (51.7 MB) |

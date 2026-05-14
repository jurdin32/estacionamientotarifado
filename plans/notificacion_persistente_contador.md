# Plan: Notificación Persistente con Contador y Hora Actual

## Problema
La notificación persistente actual se ve "sin actividad" porque:
1. El contador solo muestra `mm:ss` (minutos:segundos), sin horas
2. No muestra la hora actual del sistema, dando la impresión de que la app está congelada
3. La notificación se actualiza cada 2 segundos en lugar de cada 1 segundo

## Solución

### Cambios en [`ServicioPersistente.kt`](android/app/src/main/kotlin/com/simert/estacionamientotarifado/ServicioPersistente.kt)

#### 1. Formato de tiempo: `HH:mm:ss` en lugar de `mm:ss`
Cuando los segundos restantes son >= 3600 (1 hora), mostrar `HH:mm:ss`.
Cuando son < 3600, mostrar `mm:ss` como antes.

#### 2. Hora actual en la notificación
Agregar la hora actual del sistema en el título o subtítulo de la notificación.
Formato: `HH:mm:ss` actualizándose cada segundo.

#### 3. Actualización cada 1 segundo (no cada 2)
Cambiar la condición de actualización para que siempre se actualice cada segundo.

### Diagrama de la Notificación

```
┌──────────────────────────────────────┐
│  ⏱️ 14:30:45                         │  ← Hora actual (nuevo)
│                                      │
│  🅿️ SIMERT Estacionamientos          │  ← Título
│                                      │
│  #5 - ABC-1234  ⏱️ 00:45:30          │  ← Tarjeta más próxima con HH:mm:ss
│  🔹 #3 - XYZ-789  ⏱️ 01:20:00  👤 Juan│  ← Otras tarjetas
│  🔹 #8 - DEF-456  ⏱️ 01:45:00  👤 María│
│                                      │
│  3 estacionamiento(s) activo(s)      │  ← Resumen
└──────────────────────────────────────┘
```

### Cambios Específicos

#### Cambio 1: Formatear tiempo con horas
```kotlin
private fun formatearTiempo(segundos: Long): String {
    val h = segundos / 3600
    val m = (segundos % 3600) / 60
    val s = segundos % 60
    return if (h > 0) {
        String.format("%02d:%02d:%02d", h, m, s)
    } else {
        String.format("%02d:%02d", m, s)
    }
}
```

#### Cambio 2: Obtener hora actual
```kotlin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private fun horaActual(): String {
    val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    return sdf.format(Date())
}
```

#### Cambio 3: Modificar `mostrarNotificacionLista()`
- Agregar hora actual en el título
- Usar `formatearTiempo()` en lugar de `String.format("%02d:%02d", ...)`
- Actualizar cada 1 segundo (cambiar condición en `actualizarCuentaRegresiva()`)

#### Cambio 4: Modificar `actualizarCuentaRegresiva()`
- Cambiar `segundosRestantes % 2 == 0L` a `true` (siempre actualizar)
- O mantener cada 2 segundos pero mostrar la hora actual que cambia cada segundo

### Código Modificado

```kotlin
private fun formatearTiempo(segundos: Long): String {
    val h = segundos / 3600
    val m = (segundos % 3600) / 60
    val s = segundos % 60
    return if (h > 0) {
        String.format("%02d:%02d:%02d", h, m, s)
    } else {
        String.format("%02d:%02d", m, s)
    }
}

private fun horaActual(): String {
    val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    return sdf.format(Date())
}
```

Y en `mostrarNotificacionLista()`:
```kotlin
val tiempo = formatearTiempo(segundosRestantes)
val hora = horaActual()
val titulo = "\u23F0 $hora  |  #${mejor.numero} - ${mejor.placa}  \u23F1 $tiempo"
```

## Archivos a Modificar
| Archivo | Cambios |
|---------|---------|
| `android/app/src/main/kotlin/.../ServicioPersistente.kt` | 4 cambios |

## Pruebas de Verificación
1. Abrir app con tarjetas activas → notificación muestra hora actual + contador
2. El contador debe decrementar en tiempo real
3. La hora actual debe actualizarse cada segundo
4. Al no haber tarjetas activas, mostrar "Sin estacionamientos activos" + hora actual

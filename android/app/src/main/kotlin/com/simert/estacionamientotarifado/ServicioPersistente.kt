package com.simert.estacionamientotarifado

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Timer
import java.util.TimerTask
import org.json.JSONArray
import org.json.JSONObject

/**
 * Servicio Foreground Android diseñado para:
 *
 * 1. MANTENER LA APP VIVA: Mientras este servicio corra, Android NO puede
 *    matar el proceso (aunque el usuario deslice en multitasking).
 *
 * 2. RECIBIR DATOS DESDE FLUTTER VÍA INTENT: Flutter envía las tarjetas
 *    activas directamente a través del MethodChannel. El servicio las
 *    mantiene en memoria y actualiza la notificación.
 *
 * 3. NOTIFICACIÓN CON CUENTA REGRESIVA + HORA ACTUAL: Muestra en la barra
 *    de estado la hora actual y todas las tarjetas activas con tiempo
 *    restante en tiempo real (HH:mm:ss). La hora actual se actualiza
 *    cada segundo para mostrar que la app está activa.
 *    Esta notificación NO se cierra cuando la app Flutter se cierra.
 *
 * 4. START_STICKY + AUTO-REINICIO: Si Android lo mata (extrema presión
 *    de memoria), se reinicia solo y sigue funcionando.
 *
 * NOTA: El servidor libera automáticamente cuando el tiempo expira.
 * La app NO necesita llamar a liberarEnServidor(). Solo la liberación
 * manual se maneja desde la UI de Flutter.
 */
class ServicioPersistente : Service() {

    companion object {
        private const val TAG = "SIMERT_Servicio"
        private const val NOTIFICACION_ID = 99
        private const val CHANNEL_ID = "servicio_persistente_channel"
    }

    private var timerNotificacion: Timer? = null
    private val handler = Handler(Looper.getMainLooper())

    // Lista de tarjetas activas en memoria (recibidas desde Flutter vía Intent)
    private val tarjetasMemoria = mutableListOf<TarjetaActiva>()

    // Variables de estado de la notificación
    private var ultimoEstacionId = -1
    private var segundosRestantes = 0L

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "=== ServicioPersistente INICIADO (datos desde Flutter) ===")
        crearCanalNotificacion()

        // Mostrar notificación inicial inmediatamente
        try {
            mostrarNotificacionLista(emptyList())
        } catch (e: Exception) {
            Log.e(TAG, "Error en onCreate: ${e.message}")
            val notif = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("SIMERT Estacionamientos")
                .setContentText("Iniciando monitoreo...")
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setOngoing(true)
                .setAutoCancel(false)
                .build()
            startForeground(NOTIFICACION_ID, notif)
        }

        // Timer: cuenta regresiva cada 1s sobre datos en memoria
        timerNotificacion = Timer("notifTimer", true).apply {
            schedule(object : TimerTask() {
                override fun run() = actualizarCuentaRegresiva()
            }, 0, 1_000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            intent?.let {
                // Recibir datos de tarjetas activas desde Flutter
                val tarjetasJson = it.getStringExtra("tarjetas_json")
                if (!tarjetasJson.isNullOrEmpty()) {
                    Log.d(TAG, "onStartCommand: Recibido tarjetas_json (${tarjetasJson.length} chars)")
                    procesarTarjetasDesdeFlutter(tarjetasJson)
                } else {
                    Log.w(TAG, "onStartCommand: tarjetas_json está vacío o es null")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error en onStartCommand: ${e.message}")
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "Servicio destruido — reiniciando inmediatamente")
        timerNotificacion?.cancel()
        timerNotificacion = null
        super.onDestroy()
        // Auto-reinicio
        try {
            val intent = Intent(this, ServicioPersistente::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(intent)
            else
                startService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error reiniciando: ${e.message}")
        }
    }

    // ==================================================================
    //  RECEPCIÓN DE DATOS DESDE FLUTTER
    //  Flutter envía las tarjetas activas vía MethodChannel → Intent
    // ==================================================================

    /**
     * Procesa el JSON de tarjetas activas recibido desde Flutter.
     * El JSON tiene el formato:
     * [
     *   {"estacionId": 1, "numero": 1, "placa": "ABC-123",
     *    "usuario": 5, "usuarioNombre": "Juan", "segundos": 3600},
     *   ...
     * ]
     */
    private fun procesarTarjetasDesdeFlutter(json: String) {
        try {
            Log.d(TAG, "📥 Procesando tarjetas JSON (${json.length} chars): ${json.take(200)}...")
            tarjetasMemoria.clear()
            val arr = JSONArray(json)
            Log.d(TAG, "📦 Array contiene ${arr.length()} elementos")
            
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val estacionId = obj.optInt("estacionId", -1)
                if (estacionId <= 0) {
                    Log.w(TAG, "⚠️ Elemento $i: estacionId inválido ($estacionId), saltando")
                    continue
                }
                val segs = obj.optLong("segundos", 0)
                if (segs <= 0) {
                    Log.w(TAG, "⚠️ Elemento $i (estacionId=$estacionId): segundos inválido ($segs), saltando")
                    continue
                }

                tarjetasMemoria.add(TarjetaActiva(
                    estacionId = estacionId,
                    numero = obj.optInt("numero", estacionId),
                    placa = obj.optString("placa", "S/P"),
                    usuario = obj.optInt("usuario", 0),
                    usuarioNombre = obj.optString("usuarioNombre", "Usuario"),
                    segundos = segs
                ))
                Log.d(TAG, "✅ Tarjeta agregada: #${estacionId} - ${obj.optString("placa", "S/P")} - ${segs}s")
            }
            tarjetasMemoria.sortBy { it.segundos }
            Log.d(TAG, "✨ Recibidas ${tarjetasMemoria.size} tarjetas válidas desde Flutter")

            // Actualizar estado de la notificación
            if (tarjetasMemoria.isNotEmpty()) {
                val mejor = tarjetasMemoria.first()
                ultimoEstacionId = mejor.estacionId
                segundosRestantes = mejor.segundos
                Log.d(TAG, "🎯 Enfoque en: #${mejor.numero} (${mejor.segundos}s restantes)")
            } else {
                ultimoEstacionId = -1
                segundosRestantes = 0
                Log.i(TAG, "🔔 Sin tarjetas activas - mostrando notificación vacía")
            }
            handler.post { mostrarNotificacionLista(tarjetasMemoria.toList()) }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error parseando tarjetas desde Flutter: ${e.message}", e)
        }
    }

    data class TarjetaActiva(
        val estacionId: Int, val numero: Int, val placa: String, val usuario: Int,
        val usuarioNombre: String, val segundos: Long
    )

    // ==================================================================
    //  CUENTA REGRESIVA
    //  Trabaja sobre los datos en memoria recibidos desde Flutter.
    //  Cuando una tarjeta expira, se elimina de la lista en memoria.
    //  Flutter es responsable de limpiar SharedPreferences.
    // ==================================================================

    private fun actualizarCuentaRegresiva() {
        if (tarjetasMemoria.isEmpty()) {
            if (ultimoEstacionId > 0) {
                Log.i(TAG, "Ya no hay tarjetas activas en memoria")
                ultimoEstacionId = -1
            }
            handler.post { mostrarNotificacionLista(emptyList()) }
            return
        }

        // Decrementar el contador de la primera tarjeta (la más próxima a expirar)
        val primera = tarjetasMemoria.first()
        if (primera.estacionId == ultimoEstacionId) {
            segundosRestantes--
            if (segundosRestantes <= 0) {
                Log.i(TAG, "⏰ #$ultimoEstacionId EXPIRÓ — eliminando de memoria")
                tarjetasMemoria.removeAll { it.estacionId == ultimoEstacionId }
                ultimoEstacionId = -1
                segundosRestantes = 0
                handler.post { mostrarNotificacionLista(tarjetasMemoria.toList()) }
                return
            }
            // Actualizar el objeto en memoria con el nuevo tiempo
            val idx = tarjetasMemoria.indexOfFirst { it.estacionId == ultimoEstacionId }
            if (idx >= 0) {
                tarjetasMemoria[idx] = tarjetasMemoria[idx].copy(segundos = segundosRestantes)
            }
        } else {
            // Cambió la tarjeta más próxima (llegaron datos nuevos desde Flutter)
            ultimoEstacionId = primera.estacionId
            segundosRestantes = primera.segundos
        }

        // Actualizar notificación cada 1 segundo para que la hora actual se vea en tiempo real
        handler.post { mostrarNotificacionLista(tarjetasMemoria.toList()) }
    }

    // ==================================================================
    //  NOTIFICACIONES
    //  Siempre visibles, nunca se cierran.
    //  Muestran TODAS las tarjetas activas en formato de lista
    //  con la hora actual y contador regresivo en HH:mm:ss.
    // ==================================================================

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

    private fun mostrarNotificacionLista(tarjetas: List<TarjetaActiva>) {
        try {
            val hora = horaActual()

            if (tarjetas.isEmpty()) {
                val notif = Notification.Builder(this, CHANNEL_ID)
                    .setContentTitle("\u23F0 SIMERT Estacionamientos")
                    .setContentText("Hora actual: $hora")
                    .setSmallIcon(android.R.drawable.ic_menu_compass)
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setShowWhen(false)
                    .build()
                startForeground(NOTIFICACION_ID, notif)
                return
            }

            // Construir título con hora actual + tarjeta más próxima
            val mejor = tarjetas.first()
            val tiempo = formatearTiempo(segundosRestantes)
            val titulo = "\u23F0 $hora  |  #${mejor.numero} ${mejor.placa}  \u23F1 $tiempo"

            // Construir líneas para InboxStyle (una por tarjeta activa)
            val lines = mutableListOf<String>()
            for ((i, t) in tarjetas.withIndex()) {
                val tTiempo = formatearTiempo(t.segundos)
                val icono = if (i == 0) "\u2B06" else "\uD83D\uDD39"
                lines.add("$icono #${t.numero} ${t.placa}  \u23F1 $tTiempo  \uD83D\uDC64 ${t.usuarioNombre}")
            }

            val inboxStyle = Notification.InboxStyle()
            inboxStyle.setBigContentTitle("\u23F0 SIMERT Estacionamientos  $hora")
            for (line in lines) {
                inboxStyle.addLine(line)
            }
            inboxStyle.setSummaryText("${tarjetas.size} estacionamiento(s) activo(s)")

            val notif = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(titulo)
                .setContentText(lines.first())
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setOngoing(true)
                .setAutoCancel(false)
                .setShowWhen(false)
                .setStyle(inboxStyle)
                .build()
            startForeground(NOTIFICACION_ID, notif)
        } catch (e: Exception) {
            Log.e(TAG, "Error notificación: ${e.message}")
        }
    }

    private fun crearCanalNotificacion() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "SIMERT Estacionamientos",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitoreo de estacionamientos en tiempo real"
                setShowBadge(false)
                setSound(null, null)
            }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(channel)
        }
    }
}

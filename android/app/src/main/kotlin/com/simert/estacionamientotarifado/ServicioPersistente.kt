package com.simert.estacionamientotarifado

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import org.json.JSONArray
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.Timer
import java.util.TimerTask

/**
 * Servicio Foreground Android diseñado para:
 *
 * 1. MANTENER LA APP VIVA: Mientras este servicio corra, Android NO puede
 *    matar el proceso (aunque el usuario deslice en multitasking).
 *
 * 2. CONSULTAR LA API REAL cada 30s: Obtiene estaciones y tarjetas
 *    directamente del servidor, SIN depender del caché de Flutter.
 *
 * 3. ACTUALIZAR SHAREDPREFERENCES: Cada vez que sincroniza, escribe los
 *    datos actualizados en las mismas SharedPreferences que usa Flutter,
 *    para que la interfaz refleje los cambios reales del servidor.
 *
 * 4. NOTIFICACIÓN CON CUENTA REGRESIVA: Muestra en la barra de estado
 *    la tarjeta más próxima a expirar, con tiempo restante en tiempo real.
 *
 * 5. LIBERAR EN EL SERVIDOR: Cuando una tarjeta llega a 0, envía la
 *    liberación al servidor automáticamente.
 *
 * 6. START_STICKY + AUTO-REINICIO: Si Android lo mata (extrema presión
 *    de memoria), se reinicia solo y sigue funcionando.
 */
class ServicioPersistente : Service() {

    companion object {
        private const val TAG = "SIMERT_Servicio"
        private const val NOTIFICACION_ID = 99
        private const val CHANNEL_ID = "servicio_persistente_channel"
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"
        private const val API_BASE = "https://simert.transitoelguabo.gob.ec/api"
        private const val KEY_TOKEN = "flutter.token"
        private const val KEY_ID = "flutter.id"
        private const val KEY_NAME = "flutter.name"
    }

    private var timerSync: Timer? = null
    private var timerNotificacion: Timer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val dateFormatFecha = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

    // Variables de estado de la notificación
    private var ultimoEstacionId = -1
    private var ultimaPlaca = ""
    private var ultimoUsuario = ""
    private var segundosRestantes = 0L

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "=== ServicioPersistente INICIADO ===")
        crearCanalNotificacion()
        mostrarNotificacion("SIMERT", "Iniciando monitoreo...")

        // Timer: sincronizar con servidor cada 30s
        timerSync = Timer("syncTimer", true).apply {
            schedule(object : TimerTask() {
                override fun run() = sincronizarConServidor()
            }, 0, 30_000L)
        }

        // Timer: cuenta regresiva cada 1s
        timerNotificacion = Timer("notifTimer", true).apply {
            schedule(object : TimerTask() {
                override fun run() = actualizarCuentaRegresiva()
            }, 0, 1_000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Si recibimos un Intent con extras (desde MainActivity), procesarlos
        intent?.let {
            val token = it.getStringExtra("token")
            if (!token.isNullOrEmpty()) {
                guardarEnFlutterPrefs(KEY_TOKEN, token)
                Log.i(TAG, "Token actualizado desde Flutter vía Intent")
            }
            val nombre = it.getStringExtra("nombre_usuario")
            if (!nombre.isNullOrEmpty()) guardarEnFlutterPrefs(KEY_NAME, nombre)
            val id = it.getIntExtra("id_usuario", -1)
            if (id > 0) guardarEnFlutterPrefs(KEY_ID, id)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "Servicio destruido — reiniciando inmediatamente")
        timerSync?.cancel()
        timerNotificacion?.cancel()
        timerSync = null
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
    //  SINCRONIZACIÓN PRINCIPAL
    // ==================================================================

    /**
     * 1. Obtiene token desde SharedPreferences de Flutter
     * 2. Consulta estaciones y tarjetas del servidor
     * 3. Filtra solo las que están ocupadas + del día de hoy + con tiempo > 0
     * 4. Selecciona la de MENOR tiempo restante
     * 5. Actualiza SharedPreferences de Flutter para que la UI se refleje
     * 6. Muestra la notificación con cuenta regresiva
     */
    private fun sincronizarConServidor() {
        try {
            val token = leerFlutterPrefs(KEY_TOKEN)
            if (token.isNullOrEmpty()) {
                Log.w(TAG, "Sin token — reintentando en 30s")
                mostrarNotificacion("SIMERT", "Esperando inicio de sesión...")
                return
            }

            // Consultar API
            val estacionesJson = consultarApi("$API_BASE/estacionamientos/?_tk=$token") ?: return
            val tarjetasJson = consultarApi("$API_BASE/estacionamientos_tarjeta/?_tk=$token") ?: return

            // Parsear estaciones ocupadas
            val estacionesOcupadas = mutableSetOf<Int>()
            val estacionesList = mutableListOf<Map<String, Any?>>()
            try {
                val arr = JSONArray(estacionesJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val id = obj.optInt("id", -1)
                    val estado = obj.optBoolean("estado", false)
                    val placa = obj.optString("placa", "")
                    val nombre = obj.optString("nombre", "")
                    if (id > 0 && estado) estacionesOcupadas.add(id)
                    estacionesList.add(mapOf(
                        "id" to id,
                        "estado" to estado,
                        "placa" to placa,
                        "nombre" to nombre
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error parseando estaciones: ${e.message}")
                return
            }

            val ahora = Calendar.getInstance()
            val hoy = dateFormatFecha.format(ahora.time)

            // Parsear tarjetas
            data class Tarjeta(
                val estacionId: Int, val placa: String, val usuario: Int,
                val usuarioNombre: String, val segundos: Long
            )

            val tarjetasActivas = mutableListOf<Tarjeta>()
            val tarjetasList = mutableListOf<Map<String, Any?>>()

            try {
                val arr = JSONArray(tarjetasJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val estacionId = obj.optInt("estacion_id", -1)
                    if (estacionId <= 0) continue
                    val fecha = obj.optString("fecha", "")
                    if (fecha != hoy) continue
                    if (!estacionesOcupadas.contains(estacionId)) continue

                    val horaSalida = obj.optString("hora_salida", "")
                    if (horaSalida.isEmpty()) continue

                    val segs = calcularSegundosRestantes(horaSalida)
                    if (segs == null || segs <= 0) continue

                    val placa = obj.optString("placa", "S/P")
                    val usuario = obj.optInt("usuario", 0)
                    val usuarioNombre = obj.optString("usuario_nombre", "")
                    val horaEntrada = obj.optString("hora_entrada", "")

                    tarjetasActivas.add(Tarjeta(estacionId, placa, usuario, usuarioNombre, segs))
                    tarjetasList.add(mapOf(
                        "estacion_id" to estacionId,
                        "placa" to placa,
                        "usuario" to usuario,
                        "usuario_nombre" to usuarioNombre,
                        "fecha" to fecha,
                        "hora_entrada" to horaEntrada,
                        "hora_salida" to horaSalida,
                        "estacionId" to estacionId
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error parseando tarjetas: ${e.message}")
                return
            }

            // ACTUALIZAR SHAREDPREFERENCES DE FLUTTER con datos reales del servidor
            // Esto hace que la interfaz de Flutter refleje los cambios inmediatamente
            actualizarSharedPreferences(estacionesList, tarjetasList, estacionesOcupadas)

            // Actualizar notificación con la tarjeta más próxima a expirar
            handler.post {
                if (tarjetasActivas.isEmpty()) {
                    if (ultimoEstacionId > 0) {
                        Log.i(TAG, "Ya no hay tarjetas activas")
                        ultimoEstacionId = -1
                    }
                    mostrarNotificacion("SIMERT", "Sin estacionamientos activos")
                } else {
                    // Ordenar por menor tiempo y tomar la primera
                    val mejor = tarjetasActivas.minByOrNull { it.segundos }!!
                    if (mejor.estacionId != ultimoEstacionId) {
                        Log.i(TAG, "Mostrando #${mejor.estacionId} - ${mejor.segundos}s restantes")
                        ultimoEstacionId = mejor.estacionId
                        ultimaPlaca = mejor.placa
                        ultimoUsuario = if (mejor.usuarioNombre.isNotEmpty())
                            mejor.usuarioNombre
                        else
                            "Usuario"
                    }
                    segundosRestantes = mejor.segundos
                    mostrarNotificacionCuentaRegresiva()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error en sync: ${e.message}")
        }
    }

    // ==================================================================
    //  ACTUALIZAR SHAREDPREFERENCES (para que la UI de Flutter se refleje)
    // ==================================================================

    /**
     * Escribe los datos actualizados del servidor en las SharedPreferences
     * que usa Flutter, para que cuando la app esté abierta, los widgets
     * vean los datos correctos al hacer setState o al recargar.
     */
    private fun actualizarSharedPreferences(
        estaciones: List<Map<String, Any?>>,
        tarjetas: List<Map<String, Any?>>,
        estacionesOcupadas: Set<Int>
    ) {
        try {
            val prefs = getSharedPreferences(PREFS_FLUTTER, MODE_PRIVATE)

            // 1. Guardar estaciones actualizadas
            val estJson = JSONArray()
            for (e in estaciones) {
                val obj = org.json.JSONObject()
                obj.put("id", e["id"] as? Int ?: -1)
                obj.put("estado", e["estado"] as? Boolean ?: false)
                obj.put("placa", e["placa"] as? String ?: "")
                obj.put("nombre", e["nombre"] as? String ?: "")
                estJson.put(obj)
            }
            prefs.edit().putString("estacionamientos", estJson.toString()).apply()

            // 2. Guardar tarjetas actualizadas (solo las activas)
            val tarJson = JSONArray()
            for (t in tarjetas) {
                val obj = org.json.JSONObject()
                obj.put("estacion_id", t["estacion_id"] as? Int ?: -1)
                obj.put("placa", t["placa"] as? String ?: "")
                obj.put("usuario", t["usuario"] as? Int ?: 0)
                obj.put("usuario_nombre", t["usuario_nombre"] as? String ?: "")
                obj.put("fecha", t["fecha"] as? String ?: "")
                obj.put("hora_entrada", t["hora_entrada"] as? String ?: "")
                obj.put("hora_salida", t["hora_salida"] as? String ?: "")
                obj.put("estacionId", t["estacionId"] as? Int ?: -1)
                tarJson.put(obj)
            }
            prefs.edit().putString("estacionamientos_tarjeta", tarJson.toString()).apply()

            Log.d(TAG, "SharedPreferences actualizados: ${estaciones.size} est, ${tarjetas.size} tar")
        } catch (e: Exception) {
            Log.e(TAG, "Error actualizando SharedPreferences: ${e.message}")
        }
    }

    // ==================================================================
    //  CUENTA REGRESIVA Y LIBERACIÓN
    // ==================================================================

    private fun actualizarCuentaRegresiva() {
        if (ultimoEstacionId <= 0 || segundosRestantes <= 0) return

        segundosRestantes--
        if (segundosRestantes <= 0) {
            // La tarjeta expiró — liberar en servidor y actualizar caché
            Log.i(TAG, "⏰ #$ultimoEstacionId EXPIRÓ — liberando...")
            liberarEnServidor(ultimoEstacionId)
            ultimoEstacionId = -1
            // Forzar sincronización inmediata para actualizar SharedPreferences
            sincronizarConServidor()
            return
        }
        // Actualizar notificación cada 5 segundos para no saturar
        if (segundosRestantes % 5 == 0L || segundosRestantes < 10) {
            handler.post { mostrarNotificacionCuentaRegresiva() }
        }
    }

    private fun liberarEnServidor(estacionId: Int) {
        try {
            val token = leerFlutterPrefs(KEY_TOKEN) ?: return
            // GET
            consultarApi("$API_BASE/liberar_estacionamiento.php?estacion_id=$estacionId&_tk=$token")
            // POST (más confiable)
            try {
                val url = URL("$API_BASE/liberar_estacionamiento.php")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.connectTimeout = 8_000
                conn.readTimeout = 8_000
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                OutputStreamWriter(conn.outputStream).use {
                    it.write("estacion_id=$estacionId&_tk=$token")
                    it.flush()
                }
                Log.i(TAG, "Liberación #$estacionId: HTTP ${conn.responseCode}")
                conn.disconnect()
            } catch (e: Exception) {
                Log.w(TAG, "POST liberar falló: ${e.message}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error liberando #$estacionId: ${e.message}")
        }
    }

    // ==================================================================
    //  NOTIFICACIONES
    // ==================================================================

    private fun mostrarNotificacionCuentaRegresiva() {
        if (ultimoEstacionId <= 0) return
        val min = segundosRestantes / 60
        val seg = segundosRestantes % 60
        val tiempo = String.format("%02d:%02d", min, seg)
        mostrarNotificacion("#$ultimoEstacionId - $ultimaPlaca", "\u23F1 $tiempo restante | \uD83D\uDC64 $ultimoUsuario")
    }

    private fun mostrarNotificacion(titulo: String, contenido: String) {
        try {
            val notif = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(titulo)
                .setContentText(contenido)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setOngoing(true)
                .setAutoCancel(false)
                .setShowWhen(false)
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

    // ==================================================================
    //  SHAREDPREFERENCES — LECTURA/ESCRITURA DIRECTA de las de Flutter
    // ==================================================================

    private fun leerFlutterPrefs(key: String): String? {
        return try {
            getSharedPreferences(PREFS_FLUTTER, MODE_PRIVATE).getString(key, null)
        } catch (e: Exception) { null }
    }

    private fun guardarEnFlutterPrefs(key: String, value: String) {
        try {
            getSharedPreferences(PREFS_FLUTTER, MODE_PRIVATE)
                .edit().putString(key, value).apply()
        } catch (e: Exception) {
            Log.w(TAG, "Error guardando $key: ${e.message}")
        }
    }

    private fun guardarEnFlutterPrefs(key: String, value: Int) {
        try {
            getSharedPreferences(PREFS_FLUTTER, MODE_PRIVATE)
                .edit().putInt(key, value).apply()
        } catch (e: Exception) {
            Log.w(TAG, "Error guardando $key: ${e.message}")
        }
    }

    // ==================================================================
    //  CONSULTA HTTP
    // ==================================================================

    private fun consultarApi(urlStr: String): String? {
        return try {
            val conn = URL(urlStr).openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Accept", "application/json")
            val code = conn.responseCode
            if (code != 200) {
                Log.w(TAG, "API $code: ${urlStr.take(80)}")
                return null
            }
            BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
        } catch (e: Exception) {
            Log.w(TAG, "Error HTTP: ${e.message}")
            null
        }
    }

    // ==================================================================
    //  CÁLCULO DE TIEMPO
    // ==================================================================

    private fun calcularSegundosRestantes(horaSalida: String): Long? {
        try {
            val ahora = Calendar.getInstance()
            val partes = horaSalida.split(":")
            if (partes.size < 2) return null
            val hh = partes[0].replace("\\D".toRegex(), "").toIntOrNull() ?: 0
            val mm = partes[1].replace("\\D".toRegex(), "").toIntOrNull() ?: 0
            val ss = if (partes.size >= 3)
                partes[2].replace("\\D".toRegex(), "").toIntOrNull() ?: 0 else 0

            val salida = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hh); set(Calendar.MINUTE, mm)
                set(Calendar.SECOND, ss); set(Calendar.MILLISECOND, 0)
            }
            if (salida.timeInMillis <= ahora.timeInMillis)
                salida.add(Calendar.DAY_OF_MONTH, 1)

            val diff = salida.timeInMillis - ahora.timeInMillis
            return if (diff <= 0) null else diff / 1000
        } catch (e: Exception) { return null }
    }
}

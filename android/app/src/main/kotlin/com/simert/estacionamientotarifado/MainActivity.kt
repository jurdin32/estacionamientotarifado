package com.simert.estacionamientotarifado

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "com.simert.estacionamiento/minimizar"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        iniciarServicioPersistente()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "minimizar" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "enviarToken" -> {
                    val args = call.arguments as? Map<String, Any>
                    val token = args?.get("token") as? String
                    val nombre = args?.get("nombre_usuario") as? String
                    val id = (args?.get("id_usuario") as? Int) ?: -1

                    if (!token.isNullOrEmpty()) {
                        val intent = Intent(this, ServicioPersistente::class.java).apply {
                            putExtra("token", token)
                            if (!nombre.isNullOrEmpty()) putExtra("nombre_usuario", nombre)
                            if (id > 0) putExtra("id_usuario", id)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    }
                    result.success(true)
                }
                "enviarTarjetasActivas" -> {
                    // Flutter envía las tarjetas activas directamente al servicio nativo
                    val tarjetasJson = call.arguments as? String
                    android.util.Log.d("SIMERT", "[CHANNEL] Recibido enviarTarjetasActivas: $tarjetasJson")
                    if (!tarjetasJson.isNullOrEmpty()) {
                        try {
                            val intent = Intent(this, ServicioPersistente::class.java).apply {
                                putExtra("tarjetas_json", tarjetasJson)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            android.util.Log.d("SIMERT", "[CHANNEL] ✅ Servicio iniciado con tarjetas")
                            result.success("OK")
                        } catch (e: Exception) {
                            android.util.Log.e("SIMERT", "[CHANNEL] ❌ Error iniciando servicio: ${e.message}")
                            result.error("START_SERVICE_FAILED", e.message, null)
                        }
                    } else {
                        android.util.Log.w("SIMERT", "[CHANNEL] tarjetasJson está vacío")
                        result.success("EMPTY_DATA")
                    }
                }
            }
        }
    }

    override fun onBackPressed() {
        super.onBackPressed()
        moveTaskToBack(true)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
    }

    override fun onStop() {
        super.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        iniciarServicioPersistente()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
    }

    private fun iniciarServicioPersistente() {
        try {
            val intent = Intent(this, ServicioPersistente::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            android.util.Log.w("SIMERT", "No se pudo iniciar servicio: ${e.message}")
        }
    }
}

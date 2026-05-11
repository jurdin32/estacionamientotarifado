import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:estacionamientotarifado/core/colores.dart';

/// Pantalla que se muestra cuando hay una actualización obligatoria disponible.
/// El usuario no puede continuar usando la app hasta que actualice.
class ActualizacionForzadaScreen extends StatelessWidget {
  final String versionDisponible;
  final String urlPlayStore;
  final String? mensaje;

  const ActualizacionForzadaScreen({
    super.key,
    required this.versionDisponible,
    required this.urlPlayStore,
    this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Bloquear botón de retroceso
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppColores.gradientePrincipal,
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // Icono de actualización
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                // Título
                const Text(
                  'Actualización',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Disponible v$versionDisponible',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 40),
                // Mensaje opcional
                if (mensaje != null && mensaje!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      mensaje!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
                // Descripción
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Es necesario actualizar la aplicación para continuar usando SIMERT Estacionamientos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
                const Spacer(flex: 1),
                // Botón de actualizar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0A1628),
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.update_rounded, size: 24),
                      label: const Text(
                        'Actualizar ahora',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      onPressed: () => _abrirPlayStore(context),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Texto informativo
                TextButton(
                  onPressed: () => _abrirPlayStore(context),
                  child: Text(
                    'Play Store',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrirPlayStore(BuildContext context) async {
    try {
      final uri = Uri.parse(urlPlayStore);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: intentar abrir en el navegador
        final fallbackUri = Uri.parse(
          'https://play.google.com/store/apps/details?id=com.simert.estacionamientotarifado',
        );
        if (await canLaunchUrl(fallbackUri)) {
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error abriendo Play Store: $e');
    }
  }
}

import 'package:estacionamientotarifado/login_screan.dart';
import 'package:estacionamientotarifado/screens/actualizacion_forzada_screen.dart';
import 'package:estacionamientotarifado/servicios/servicioActualizacionForzada.dart';
import 'package:estacionamientotarifado/shared/widgets/fondo_decorado_app.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));

    _ctrl.forward();

    _iniciarVerificacion();
  }

  /// Inicia la verificación de actualización y luego el login
  Future<void> _iniciarVerificacion() async {
    // Verificar si hay actualización forzada
    final resultado = await ServicioActualizacionForzada.verificar();

    if (!mounted) return;

    // Si hay actualización forzada, mostrar pantalla de actualización
    if (resultado != null &&
        resultado.hayActualizacion &&
        resultado.esForzada) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ActualizacionForzadaScreen(
            versionDisponible: resultado.versionDisponible,
            urlPlayStore: resultado.urlPlayStore,
            mensaje: resultado.mensaje,
          ),
        ),
      );
      return;
    }

    // Continuar con el flujo normal de login
    await _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    await Future.delayed(const Duration(seconds: 1)); // Carga inicial

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTabletLike = shortestSide > 600;

    return Scaffold(
      body: FondoDecoradoApp(
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isTabletLike ? 28 : 20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/simert.png',
                            height: isTabletLike ? 170 : 140,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: const Text(
                            'Sistema Municipal de Estacionamiento',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'SIMERT',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: isTabletLike ? 46 : 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Control ágil de usuarios, infracciones y tarjetas en una sola experiencia.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: isTabletLike ? 18 : 14,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

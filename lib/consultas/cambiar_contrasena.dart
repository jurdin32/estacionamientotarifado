import 'dart:convert';
import 'package:estacionamientotarifado/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CambiarContrasenaScreen extends StatefulWidget {
  final bool forzarCambio;
  const CambiarContrasenaScreen({super.key, this.forzarCambio = false});

  @override
  State<CambiarContrasenaScreen> createState() =>
      _CambiarContrasenaScreenState();
}

class _CambiarContrasenaScreenState extends State<CambiarContrasenaScreen> {
  static const _colorPrimario = Color(0xFF001F54);
  static const _colorSecundario = Color(0xFF5E17EB);

  final _formKey = GlobalKey<FormState>();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _obscureActual = true;
  bool _obscureNueva = true;
  bool _obscureConfirmar = true;
  bool _cargando = false;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiarContrasena() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String username = prefs.getString('username') ?? '';
      final String token = prefs.getString('token') ?? '';

      if (username.isEmpty || token.isEmpty) {
        _mostrarMensaje(
          'No se pudo obtener la sesión. Inicia sesión de nuevo.',
          error: true,
        );
        return;
      }

      final response = await http.post(
        Uri.parse(
          'https://simert.transitoelguabo.gob.ec/api/auth/change_password',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({
          'username': username,
          'password_actual': _actualCtrl.text,
          'password_nueva': _nuevaCtrl.text,
        }),
      );

      debugPrint(
        '[CambiarPass] status=${response.statusCode} body=${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // La API devuelve {"detail": "...", "token": "nuevo_token"}
        final nuevoToken = data['token']?.toString() ?? '';
        if (nuevoToken.isNotEmpty) {
          // Guardar el nuevo token y actualizar la contraseña en preferencias
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', nuevoToken);
          await prefs.setString('auth_password', _nuevaCtrl.text);
        }
        _mostrarMensaje('Contraseña actualizada correctamente.', error: false);
        _actualCtrl.clear();
        _nuevaCtrl.clear();
        _confirmarCtrl.clear();
        if (widget.forzarCambio && mounted) {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        }
      } else if (response.statusCode == 400) {
        // Intentar extraer el mensaje de error del servidor DRF
        String errorMsg = 'Verifica los datos ingresados.';
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            final msgs = data.values
                .expand((v) => v is List ? v : [v])
                .map((v) => v.toString())
                .join(' ');
            if (msgs.isNotEmpty) errorMsg = msgs;
          }
        } catch (_) {}
        debugPrint('[CambiarPass] 400 detail: $errorMsg');
        _mostrarMensaje(errorMsg, error: true);
      } else {
        _mostrarMensaje(
          'Error del servidor (${response.statusCode}). Intenta más tarde.',
          error: true,
        );
      }
    } catch (e) {
      _mostrarMensaje('Error de conexión. Verifica tu red.', error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarMensaje(String texto, {required bool error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(texto)),
          ],
        ),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forzarCambio,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorSecundario],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text(
            widget.forzarCambio
                ? 'Cambio de contraseña obligatorio'
                : 'Cambiar Contraseña',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          automaticallyImplyLeading: !widget.forzarCambio,
          iconTheme: const IconThemeData(color: Colors.white),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  // Aviso en modo forzado
                  if (widget.forzarCambio)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Debes cambiar tu contraseña temporal antes de continuar.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Ícono decorativo
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_colorPrimario, _colorSecundario],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _colorSecundario.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ingresa tu nueva contraseña',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _colorPrimario,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Usa al menos 8 caracteres con letras y números.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 32),

                  // Contraseña actual
                  _buildCampo(
                    controller: _actualCtrl,
                    label: 'Contraseña actual',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscureActual,
                    onToggleObscure: () =>
                        setState(() => _obscureActual = !_obscureActual),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Este campo es obligatorio.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Nueva contraseña
                  _buildCampo(
                    controller: _nuevaCtrl,
                    label: 'Nueva contraseña',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscureNueva,
                    onToggleObscure: () =>
                        setState(() => _obscureNueva = !_obscureNueva),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Este campo es obligatorio.';
                      }
                      if (v.length < 8) {
                        return 'La contraseña debe tener al menos 8 caracteres.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirmar nueva contraseña
                  _buildCampo(
                    controller: _confirmarCtrl,
                    label: 'Confirmar contraseña',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscureConfirmar,
                    onToggleObscure: () =>
                        setState(() => _obscureConfirmar = !_obscureConfirmar),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Este campo es obligatorio.';
                      }
                      if (v != _nuevaCtrl.text) {
                        return 'Las contraseñas no coinciden.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Botón guardar
                  SizedBox(
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_colorPrimario, _colorSecundario],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _colorSecundario.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _cambiarContrasena,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _cargando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Guardar contraseña',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }

  Widget _buildCampo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(color: _colorPrimario),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: _colorSecundario),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: Colors.grey,
          ),
          onPressed: onToggleObscure,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _colorSecundario, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade400, width: 2),
        ),
      ),
    );
  }
}

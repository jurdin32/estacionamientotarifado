import 'package:estacionamientotarifado/home_screen.dart';
import 'package:estacionamientotarifado/consultas/cambiar_contrasena.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _obscurePassword = true; // estado para mostrar/ocultar contraseña

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final usuario = _userController.text.trim();
    final password = _passwordController.text.trim();

    if (usuario.isEmpty || password.isEmpty) {
      _showMessage("Por favor, completa ambos campos.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Login — obtiene token y datos del usuario en una sola llamada
      final loginResponse = await http.post(
        Uri.parse('https://simert.transitoelguabo.gob.ec/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': usuario, 'password': password}),
      );
      debugPrint(
        '[Login] api/auth/login → status=${loginResponse.statusCode} body=${loginResponse.body}',
      );
      debugPrint('[Login] headers respuesta: ${loginResponse.headers}');

      if (loginResponse.statusCode == 400 ||
          loginResponse.statusCode == 401 ||
          loginResponse.statusCode == 403) {
        _showMessage('Usuario o contraseña incorrectos.');
        return;
      }
      if (loginResponse.statusCode != 200) {
        _showMessage('Error ${loginResponse.statusCode}: no se pudo conectar.');
        return;
      }

      final loginData = json.decode(loginResponse.body) as Map<String, dynamic>;
      final drfToken = (loginData['token'] ?? '').toString().trim();
      if (drfToken.isEmpty) {
        _showMessage('Error: no se recibió token del servidor.');
        return;
      }

      // Los datos del usuario vienen dentro del campo 'user'
      final userObj = loginData['user'] is Map
          ? loginData['user'] as Map<String, dynamic>
          : loginData;
      final firstName = (userObj['first_name'] as String? ?? '').trim();
      final lastName = (userObj['last_name'] as String? ?? '').trim();
      final fullName = '$firstName $lastName'.trim();

      // Capturar la cookie de sesión que establece el servidor
      final rawCookie = loginResponse.headers['set-cookie'] ?? '';
      String sessionCookie = '';
      if (rawCookie.isNotEmpty) {
        // extraer solo "sessionid=xxx" de la cabecera Set-Cookie
        final match = RegExp(r'sessionid=[^;]+').firstMatch(rawCookie);
        if (match != null) sessionCookie = match.group(0) ?? '';
      }
      debugPrint(
        '[Login] sessionCookie: ${sessionCookie.isEmpty ? "VACÍA" : sessionCookie.substring(0, sessionCookie.length.clamp(0, 30))}...',
      );

      // Workaround: Apache elimina el header Authorization.
      // Si no hay session cookie, intentar obtenerla via /accounts/login/
      // para usar SessionAuthentication en lugar de TokenAuthentication.
      // Fix definitivo: agregar "WSGIPassAuthorization On" en Apache.
      if (sessionCookie.isEmpty) {
        sessionCookie = await _obtenerSesionDjango(usuario, password);
      }

      // 2. Guardar datos
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('id', (userObj['id'] as int?) ?? 0);
      await prefs.setString(
        'username',
        userObj['username']?.toString() ?? usuario,
      );
      await prefs.setString(
        'name',
        fullName.isNotEmpty ? fullName : userObj['name']?.toString() ?? '',
      );
      await prefs.setString('email', userObj['email']?.toString() ?? '');
      await prefs.setString('token', drfToken);
      await prefs.setString('session_cookie', sessionCookie);
      await prefs.setString('auth_usuario', usuario);
      await prefs.setString('auth_password', password);
      // Si last_login es null (primer acceso), guardar fecha actual como fallback
      final rawLastLogin = (userObj['last_login']?.toString() ?? '').trim();
      await prefs.setString(
        'last_login',
        rawLastLogin.isNotEmpty
            ? rawLastLogin
            : DateTime.now().toIso8601String(),
      );
      final isSuperuser =
          userObj['is_superuser'] == true || userObj['is_superuser'] == 'true';
      await prefs.setBool('is_superuser', isSuperuser);
      debugPrint(
        '[Login] guardado — id=${userObj['id']} is_superuser=$isSuperuser token=${drfToken.substring(0, drfToken.length.clamp(0, 10))}...',
      );

      final mustChange = prefs.getBool('must_change_password') ?? false;
      if (mustChange) {
        await prefs.remove('must_change_password');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const CambiarContrasenaScreen(forzarCambio: true),
          ),
        );
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      _showMessage('Error de red: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Workaround para Apache/mod_wsgi que elimina el header Authorization.
  /// Obtiene un sessionid de Django via /accounts/login/ para usar SessionAuthentication.
  static Future<String> _obtenerSesionDjango(
    String usuario,
    String password,
  ) async {
    const base = 'https://simert.transitoelguabo.gob.ec';
    final ioClient = HttpClient();
    try {
      // Paso 1: GET /accounts/login/ → obtener csrftoken cookie
      final req1 = await ioClient.getUrl(Uri.parse('$base/accounts/login/'));
      req1.followRedirects = false;
      req1.headers.set('accept', 'text/html');
      final resp1 = await req1.close();
      await resp1.drain<void>();
      debugPrint(
        '[Login] session-workaround GET /accounts/login/ → ${resp1.statusCode}',
      );
      if (resp1.statusCode != 200) return '';

      // Extraer csrftoken de las cookies de la respuesta
      String csrfValue = '';
      for (final c in resp1.cookies) {
        if (c.name == 'csrftoken') {
          csrfValue = c.value;
          break;
        }
      }
      if (csrfValue.isEmpty) {
        // Fallback: parsear header Set-Cookie directamente
        final rawCookies = resp1.headers['set-cookie'] ?? [];
        for (final raw in rawCookies) {
          final m = RegExp(r'csrftoken=([^;,\s]+)').firstMatch(raw);
          if (m != null) {
            csrfValue = m.group(1) ?? '';
            break;
          }
        }
      }
      if (csrfValue.isEmpty) {
        debugPrint(
          '[Login] csrftoken no encontrado, session workaround no disponible',
        );
        return '';
      }
      debugPrint('[Login] csrftoken obtenido: ok');

      // Paso 2: POST /accounts/login/ con credenciales → sessionid cookie (respuesta 302)
      final bodyBytes = utf8.encode(
        'username=${Uri.encodeComponent(usuario)}'
        '&password=${Uri.encodeComponent(password)}'
        '&csrfmiddlewaretoken=${Uri.encodeComponent(csrfValue)}'
        '&next=%2F',
      );
      final req2 = await ioClient.postUrl(Uri.parse('$base/accounts/login/'));
      req2.followRedirects = false;
      req2.headers
        ..set('content-type', 'application/x-www-form-urlencoded')
        ..set('content-length', '${bodyBytes.length}')
        ..set('referer', '$base/accounts/login/');
      req2.cookies.add(Cookie('csrftoken', csrfValue));
      req2.add(bodyBytes);
      final resp2 = await req2.close();
      await resp2.drain<void>();
      debugPrint('[Login] session-workaround POST → ${resp2.statusCode}');

      // Buscar sessionid en cookies de la respuesta 302
      for (final c in resp2.cookies) {
        if (c.name == 'sessionid') {
          debugPrint('[Login] sessionid OBTENIDO via workaround');
          return 'sessionid=${c.value}';
        }
      }
      // Fallback: parsear header Set-Cookie
      final rawCookies2 = resp2.headers['set-cookie'] ?? [];
      for (final raw in rawCookies2) {
        final m = RegExp(r'sessionid=[^;]+').firstMatch(raw);
        if (m != null) {
          debugPrint('[Login] sessionid OBTENIDO via workaround (raw header)');
          return m.group(0) ?? '';
        }
      }
      debugPrint(
        '[Login] sessionid no encontrado en respuesta ${resp2.statusCode}',
      );
      return '';
    } catch (e) {
      debugPrint('[Login] session-workaround excepción (ignorando): $e');
      return '';
    } finally {
      ioClient.close();
    }
  }

  Future<void> _olvideMiContrasena() async {
    final usernameCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Recuperar contraseña',
          style: TextStyle(
            color: Color(0xFF001F54),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa tu nombre de usuario. Se generará una contraseña temporal de 6 dígitos.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: usernameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Usuario',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001F54),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (confirmed != true || usernameCtrl.text.trim().isEmpty) return;

    final username = usernameCtrl.text.trim();
    final random = Random.secure();
    final nuevaClave = List.generate(6, (_) => random.nextInt(10)).join();

    setState(() => _isLoading = true);
    try {
      final url = Uri.parse(
        'https://simert.transitoelguabo.gob.ec/api/auth/must_change_password',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password_nueva': nuevaClave}),
      );
      if (response.statusCode == 200) {
        // Marcar que en el próximo inicio de sesión debe cambiar la contraseña
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('must_change_password', true);

        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.lock_reset_rounded, color: Color(0xFF001F54)),
                SizedBox(width: 8),
                Text(
                  'Contraseña temporal',
                  style: TextStyle(
                    color: Color(0xFF001F54),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tu contraseña temporal es:'),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5E17EB)),
                  ),
                  child: Text(
                    nuevaClave,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 10,
                      color: Color(0xFF001F54),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Anota este código. Al iniciar sesión con él deberás cambiar tu contraseña obligatoriamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001F54),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      } else if (response.statusCode == 404) {
        _showMessage('Usuario no encontrado.');
      } else {
        debugPrint(
          '[Reset] status=${response.statusCode} body=${response.body}',
        );
        _showMessage('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _showMessage('Error de red: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
      elevation: 6,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fondo con gradiente como el splash
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Hero(
                    tag: "appLogo",
                    child: Image.asset('assets/images/simert.png', width: 250),
                  ),
                  Text(
                    "SIMERT - EL GUABO",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 8,
                          color: Colors.black26,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Campo usuario
                  _buildTextField(
                    controller: _userController,
                    label: "Usuario",
                    icon: Icons.person_outline,
                    obscure: false,
                  ),
                  const SizedBox(height: 20),

                  // Campo contraseña
                  _buildTextField(
                    controller: _passwordController,
                    label: "Contraseña",
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _olvideMiContrasena,
                      child: Text(
                        "¿Olvidaste tu contraseña?",
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Botón
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0066FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 6,
                        shadowColor: Colors.black45,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF0066FF),
                            )
                          : Text(
                              "Iniciar sesión",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscure,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure && _obscurePassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.15),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white),
        prefixIcon: Icon(icon, color: Colors.white),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

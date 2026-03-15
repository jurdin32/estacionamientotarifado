import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DynamicCredentialScreen extends StatefulWidget {
  const DynamicCredentialScreen({super.key});

  @override
  State<DynamicCredentialScreen> createState() =>
      _DynamicCredentialScreenState();
}

class _DynamicCredentialScreenState extends State<DynamicCredentialScreen> {
  // Datos dinámicos
  String nombreLinea1 = '';
  String nombreLinea2 = '';
  String cargo = '';
  String cedula = '';
  String email = '';
  String telefono = '';
  String gruposanguineo = '';
  String fotoUrl = '';
  String firmaUrl = '';

  bool _isLoading = true;
  bool _hasError = false;
  bool _showFront = true; // Controla si se muestra el frente o el reverso

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      // Primero intentamos cargar desde las preferencias
      await _loadFromPreferences();

      // Luego actualizamos desde la API
      await _fetchUserDataFromAPI();
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      nombreLinea1 = prefs.getString('name') ?? nombreLinea1;
      cargo = prefs.getString('cargo') ?? cargo;
      cedula = prefs.getString('cedula') ?? cedula;
      email = prefs.getString('email') ?? email;
      telefono = prefs.getString('telefono') ?? telefono;
      gruposanguineo = prefs.getString('tipo_sangre') ?? gruposanguineo;
      fotoUrl = prefs.getString('foto_usuario') ?? fotoUrl;
      firmaUrl = prefs.getString('firma') ?? '';
    });
  }

  Future<void> _fetchUserDataFromAPI() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('id');

      if (userId == null) {
        throw Exception('No user ID found in preferences');
      }

      final response = await http.get(
        Uri.parse(
          'https://simert.transitoelguabo.gob.ec/api/user_detail/?usuario=$userId',
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        if (data.isNotEmpty) {
          final userData = data[0];

          // Guardar en preferencias
          await _saveToPreferences(userData);

          // Actualizar UI
          setState(() {
            cargo = userData['cargo'] ?? cargo;
            cedula = userData['cedula'] ?? cedula;
            telefono = userData['telefono'] ?? telefono;
            gruposanguineo = userData['tipo_sangre'] ?? gruposanguineo;
            fotoUrl = userData['foto_usuario'] ?? fotoUrl;
            firmaUrl = userData['firma'] ?? '';
            _isLoading = false;
          });
        } else {
          throw Exception('No user data found');
        }
      } else {
        throw Exception('Failed to load user data: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching API data: $e');
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveToPreferences(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('cargo', userData['cargo'] ?? '');
    await prefs.setString('cedula', userData['cedula'] ?? '');
    await prefs.setString('telefono', userData['telefono'] ?? '');
    await prefs.setString('tipo_sangre', userData['tipo_sangre'] ?? '');
    await prefs.setString('foto_usuario', userData['foto_usuario'] ?? '');
    await prefs.setString('firma', userData['firma'] ?? '');
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _fetchUserDataFromAPI();
  }

  // Método para dividir el nombre en dos líneas
  List<String> _splitNameIntoTwoLines(String fullName) {
    final words = fullName.trim().split(' ');

    if (words.length <= 2) {
      // Si tiene 2 palabras o menos, poner todo en la primera línea
      return [fullName, ''];
    } else {
      // Dividir en dos partes aproximadamente iguales
      final midPoint = (words.length / 2).ceil();
      final firstLine = words.sublist(0, midPoint).join(' ');
      final secondLine = words.sublist(midPoint).join(' ');
      return [firstLine, secondLine];
    }
  }

  // Método para voltear la credencial
  void _flipCredential() {
    setState(() {
      _showFront = !_showFront;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // Tamaño adaptativo: no superar el 72% del alto de pantalla
    final maxByHeight = (screenHeight * 0.72) / 1.64;
    final credentialWidth = min(screenWidth * 0.90, maxByHeight);
    final credentialHeight = credentialWidth * 1.64;

    // Dividir el nombre en dos líneas
    final nameLines = _splitNameIntoTwoLines(nombreLinea1);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mi Credencial'),
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Actualizar datos',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF5E17EB)),
                  SizedBox(height: 16),
                  Text('Cargando datos...'),
                ],
              ),
            )
          : _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Color(0xFF001F54),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error al cargar los datos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001F54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Verifica tu conexión a internet'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refreshData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5E17EB),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _flipCredential,
                    child: _buildFlipCard(
                      credentialWidth,
                      credentialHeight,
                      nameLines,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.touch_app_rounded,
                        size: 14,
                        color: Color(0xFF5E17EB),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Toca la tarjeta para voltear',
                        style: TextStyle(
                          color: Color(0xFF5E17EB),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFlipCard(double width, double height, List<String> nameLines) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final rotateAnim = Tween(begin: pi, end: 0.0).animate(animation);
        return AnimatedBuilder(
          animation: rotateAnim,
          child: child,
          builder: (context, widget) {
            final isUnder = (ValueKey(_showFront) != widget?.key);
            final value = isUnder
                ? min(rotateAnim.value, pi / 2)
                : rotateAnim.value;

            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(value),
              alignment: Alignment.center,
              child: widget,
            );
          },
        );
      },
      child: _showFront
          ? _buildCredentialFront(width, height, nameLines)
          : _buildCredentialBack(width, height),
    );
  }

  Widget _buildCredentialFront(
    double width,
    double height,
    List<String> nameLines,
  ) {
    // Factores de escala basados en el tamaño original (250x410)
    final scaleFactor = width / 250;

    return Container(
      key: const ValueKey('front'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12 * scaleFactor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18 * scaleFactor,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: const Color.fromARGB(255, 230, 230, 230),
          width: 3 * scaleFactor,
        ),
      ),
      child: Stack(
        children: [
          // IMAGEN DE FONDO DEL CARNET (FRENTE)
          ClipRRect(
            borderRadius: BorderRadius.circular(12 * scaleFactor),
            child: Image.asset(
              'assets/images/credencial.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,

              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFF1a237e),
                  child: Center(
                    child: Text(
                      'Imagen no encontrada\nassets/images/credencial.png',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color.fromARGB(255, 255, 255, 255),
                        fontSize: 14 * scaleFactor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // CONTENIDO SUPERPUESTO
          Positioned.fill(
            child: Container(
              padding: EdgeInsets.all(20 * scaleFactor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ESPACIO PARA EL ENCABEZADO (YA INCLUIDO EN LA IMAGEN)
                  SizedBox(height: 45 * scaleFactor),

                  // FOTO DE LA PERSONA - CENTRADA
                  Center(
                    child: Container(
                      width: 110 * scaleFactor,
                      height: 110 * scaleFactor,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(55 * scaleFactor),
                        border: Border.all(
                          color: Colors.white,
                          width: 3 * scaleFactor,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8 * scaleFactor,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(55 * scaleFactor),
                        child: fotoUrl.isNotEmpty && fotoUrl != "null"
                            ? Image.network(
                                fotoUrl,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: Colors.grey.shade300,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2 * scaleFactor,
                                          ),
                                        ),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildPlaceholderPhoto(scaleFactor);
                                },
                              )
                            : _buildPlaceholderPhoto(scaleFactor),
                      ),
                    ),
                  ),

                  // NOMBRE COMPLETO EN DOS LÍNEAS - CENTRADO
                  Container(
                    margin: EdgeInsets.only(top: 15 * scaleFactor),
                    width: double.infinity,
                    child: Column(
                      children: [
                        // Primera línea del nombre
                        if (nameLines[0].isNotEmpty)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              nameLines[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13 * scaleFactor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                                height: 1.0,
                                shadows: [
                                  Shadow(
                                    blurRadius: 4 * scaleFactor,
                                    color: Colors.black,
                                    offset: const Offset(1, 1),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Segunda línea del nombre (si existe)
                        if (nameLines[1].isNotEmpty)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              nameLines[1].toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13 * scaleFactor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                                height: 1.0,
                                shadows: [
                                  Shadow(
                                    blurRadius: 4 * scaleFactor,
                                    color: Colors.black,
                                    offset: const Offset(1, 1),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // CARGO - CENTRADO (porque está debajo del nombre)
                  Container(
                    margin: EdgeInsets.only(top: 5 * scaleFactor),
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cargo,
                        style: TextStyle(
                          color: Colors.yellow.shade300,
                          fontSize: 9 * scaleFactor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          height: 1.3,
                          shadows: [
                            Shadow(
                              blurRadius: 3 * scaleFactor,
                              color: Colors.black,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        softWrap: true,
                      ),
                    ),
                  ),

                  SizedBox(height: 10 * scaleFactor),

                  // INFORMACIÓN DE CONTACTO - ALINEADO A LA IZQUIERDA
                  _buildInfoRow(cedula, 16, scaleFactor),
                  SizedBox(height: 14 * scaleFactor),
                  _buildInfoRow(email, 13, scaleFactor),
                  SizedBox(height: 14 * scaleFactor),
                  _buildInfoRow(telefono, 13, scaleFactor),
                  SizedBox(height: 10 * scaleFactor),

                  // GRUPO SANGUÍNEO - CENTRADO
                  Container(
                    margin: EdgeInsets.only(top: 1 * scaleFactor),
                    width: double.infinity,
                    child: Text(
                      gruposanguineo,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 25 * scaleFactor,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            blurRadius: 3 * scaleFactor,
                            color: Colors.black,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialBack(double width, double height) {
    // Factores de escala basados en el tamaño original (250x410)
    final scaleFactor = width / 250;

    return Container(
      key: const ValueKey('back'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12 * scaleFactor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18 * scaleFactor,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: const Color.fromARGB(255, 230, 230, 230),
          width: 3 * scaleFactor,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12 * scaleFactor),
        child: Image.asset(
          'assets/images/reverso.png', // Misma imagen para el reverso
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: const Color(0xFF1a237e),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.credit_card,
                      size: 50 * scaleFactor,
                      color: Colors.white,
                    ),
                    SizedBox(height: 10 * scaleFactor),
                    Text(
                      'Reverso de la Credencial',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18 * scaleFactor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow(String value, double baseFontSize, double scaleFactor) {
    return Padding(
      padding: EdgeInsets.only(left: 22 * scaleFactor, top: 2),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        style: TextStyle(
          color: Colors.white,
          fontSize: baseFontSize * scaleFactor,
          letterSpacing: 0.3,
          height: 1.3,
          shadows: [
            Shadow(
              blurRadius: 3 * scaleFactor,
              color: Colors.black,
              offset: const Offset(1, 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderPhoto(double scaleFactor) {
    return Container(
      color: Colors.grey.shade300,
      child: Icon(
        Icons.person,
        size: 50 * scaleFactor,
        color: Colors.grey.shade500,
      ),
    );
  }

  // Método para actualizar los datos dinámicamente
  void updateCredentialData({
    String? newNombreLinea1,
    String? newNombreLinea2,
    String? newCargo,
    String? newCedula,
    String? newEmail,
    String? newTelefono,
    String? newGrupoSanguineo,
    String? newFotoUrl,
    String? newFirmaUrl,
  }) {
    setState(() {
      nombreLinea1 = newNombreLinea1 ?? nombreLinea1;
      nombreLinea2 = newNombreLinea2 ?? nombreLinea2;
      cargo = newCargo ?? cargo;
      cedula = newCedula ?? cedula;
      email = newEmail ?? email;
      telefono = newTelefono ?? telefono;
      gruposanguineo = newGrupoSanguineo ?? gruposanguineo;
      fotoUrl = newFotoUrl ?? fotoUrl;
      firmaUrl = newFirmaUrl ?? firmaUrl;
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  // --- Design tokens --------------------------------------------------------
  static const Color _colorPrimario = Color(0xFF001F54);
  static const Color _colorSecundario = Color(0xFF5E17EB);
  static const Color _colorFondo = Color(0xFFF0F4FF);
  static const Color _colorBorde = Color(0xFFE0E0E0);
  static const Color _colorTexto = Color(0xFF333333);
  static const Color _colorSubtexto = Color(0xFF555555);

  // --- State ----------------------------------------------------------------
  final TextEditingController _plateController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _vehicleData;
  String _name = '';

  final RegExp _plateRegex = RegExp(r'^[A-Z]{3}\d{4}$|^[A-Z]{2}\d{3}[A-Z]$');

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = (prefs.getString('name') ?? prefs.getString('username') ?? '')
          .toUpperCase();
    });
  }

  Future<void> _fetchVehicle(String placa) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _vehicleData = null;
    });

    try {
      final uri = Uri.parse(
        'https://simert.transitoelguabo.gob.ec/vehiculo_request?placa=${placa.toLowerCase()}',
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && (data is Map && data.isNotEmpty)) {
          setState(() => _vehicleData = Map<String, dynamic>.from(data));
        } else {
          setState(
            () => _errorMessage = 'No se encontró vehículo con esa placa.',
          );
        }
      } else {
        setState(
          () => _errorMessage = 'Error de servidor (${response.statusCode})',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error de red: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onSearchPressed() {
    final placa = _plateController.text.trim().toUpperCase();
    if (placa.isEmpty) {
      setState(() => _errorMessage = 'Ingresa una placa.');
      return;
    }
    if (!_plateRegex.hasMatch(placa)) {
      setState(
        () => _errorMessage = 'Formato inv\u00e1lido. Ej: ABC1234 o AB123C.',
      );
      return;
    }
    _fetchVehicle(placa);
  }

  // --- Build ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildBusqueda(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                _buildError(),
              ],
              if (_isLoading) ...[const SizedBox(height: 32), _buildCargando()],
              if (_vehicleData != null && !_isLoading) ...[
                const SizedBox(height: 20),
                _buildResultado(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- AppBar ---------------------------------------------------------------
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: const Text(
        'Consulta de Vehículos',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_colorPrimario, _colorSecundario],
          ),
        ),
      ),
    );
  }

  // --- Header banner --------------------------------------------------------
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_colorPrimario, _colorSecundario],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _colorPrimario.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_car_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SIMERT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'Consulta de Vehículos',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_name.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.white70, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ingresa la placa para consultar datos del vehículo y su propietario (formato: ABC1234 o AB123C).',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Campo b�squeda -------------------------------------------------------
  Widget _buildBusqueda() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _plateController,
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) {
          if (_errorMessage != null) setState(() => _errorMessage = null);
        },
        onSubmitted: (_) => _onSearchPressed(),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _colorPrimario,
          letterSpacing: 1.5,
        ),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          hintText: 'Ej: ABC1234',
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.normal,
            letterSpacing: 0,
          ),
          labelText: 'Placa del vehículo',
          labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          border: InputBorder.none,
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _colorPrimario.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              color: _colorPrimario,
              size: 18,
            ),
          ),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _colorPrimario,
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_colorPrimario, _colorSecundario],
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: 'Buscar vehículo',
                    onPressed: _onSearchPressed,
                  ),
                ),
        ),
        inputFormatters: [
          UpperCaseTextFormatter(),
          LengthLimitingTextInputFormatter(7),
          FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
        ],
      ),
    );
  }

  // --- Error ----------------------------------------------------------------
  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade500, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Cargando -------------------------------------------------------------
  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorSecundario],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'SIMERT',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _colorPrimario,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Consultando vehículo...',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(_colorSecundario),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // --- Resultado ------------------------------------------------------------
  Widget _buildResultado() {
    final d = _vehicleData!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // -- Header gradiente ----------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorSecundario],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_filled,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d['Placa']?.toString().toUpperCase() ?? '-',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        d['Marca']?.toString() ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Text(
                    d['Color']?.toString() ?? '-',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // -- Datos ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              children: [
                // Fila de detalles t�cnicos
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: _colorFondo,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _colorBorde),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _miniStat(
                          Icons.speed_outlined,
                          'Cilindraje',
                          d['Cilindraje']?.toString() ?? '-',
                        ),
                      ),
                      Container(width: 1, height: 36, color: _colorBorde),
                      Expanded(
                        child: _miniStat(
                          Icons.fitness_center_outlined,
                          'Tonelaje',
                          '${d['Tonelaje'] ?? '-'} T',
                        ),
                      ),
                    ],
                  ),
                ),

                // Propietario
                _infoRow(
                  Icons.person_outlined,
                  'Propietario',
                  d['Propietario']?.toString() ?? '-',
                ),
                _infoRow(
                  Icons.badge_outlined,
                  'Cédula',
                  d['Cedula']?.toString() ?? '-',
                ),
                _infoRow(
                  Icons.phone_android_outlined,
                  'Celular',
                  d['Celular']?.toString() ?? '-',
                ),
                _infoRow(
                  Icons.email_outlined,
                  'Correo',
                  d['Correo']?.toString() ?? '-',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: _colorSecundario, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: _colorPrimario,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: _colorSubtexto, fontSize: 10),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.isEmpty || value == '-' || value == 'null') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _colorSecundario),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _colorSubtexto,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: _colorTexto),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convierte texto a mayúsculas mientras se escribe.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

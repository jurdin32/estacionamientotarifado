import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'dart:convert';

class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  // --- Design tokens --------------------------------------------------------
  static const Color _colorPrimario = Color(0xFF0A1628);
  static const Color _colorSecundario = Color(0xFF1565C0);
  static const Color _colorFondo = Color(0xFFF0F4FF);
  static const Color _colorBorde = Color(0xFFE0E0E0);
  static const Color _colorTexto = Color(0xFF333333);
  static const Color _colorSubtexto = Color(0xFF555555);

  // --- State ----------------------------------------------------------------
  final TextEditingController _plateController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _vehicleData;

  final RegExp _plateRegex = RegExp(r'^[A-Z]{3}\d{4}$|^[A-Z]{2}\d{3}[A-Z]$');

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
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
      final response = await HttpMonitorizado.get(uri);

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

  void _mostrarInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A1628), Color(0xFF000000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Información',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Consulta de Vehículos',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Permite consultar los datos completos de un vehículo registrado en el sistema SIMERT mediante su número de placa.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendido'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Build ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchPanel(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      _buildError(),
                      const SizedBox(height: 14),
                    ],
                    if (_isLoading) ...[
                      const SizedBox(height: 32),
                      _buildCargando(),
                    ],
                    if (_vehicleData != null && !_isLoading) ...[
                      _buildResultado(),
                    ],
                    if (!_isLoading &&
                        _vehicleData == null &&
                        _errorMessage == null)
                      _buildEmptyState(),
                  ],
                ),
              ),
            ),
          ],
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
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      backgroundColor: _colorPrimario,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1628), Color(0xFF000000)],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'Información',
          onPressed: () => _mostrarInfo(context),
        ),
      ],
    );
  }

  // --- Panel de búsqueda ---------------------------------------------------
  Widget _buildSearchPanel() {
    final size = MediaQuery.of(context).size;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Banda de encabezado
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              size.width * 0.04,
              size.width * 0.04,
              size.width * 0.04,
              size.width * 0.03,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A1628), Color(0xFF000000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(size.width * 0.025),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_car_outlined,
                    color: Colors.white,
                    size: size.width * 0.055,
                  ),
                ),
                SizedBox(width: size.width * 0.03),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SIMERT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size.width * 0.045,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Consulta de Vehículos',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: size.width * 0.03,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Campo de búsqueda
          Padding(
            padding: EdgeInsets.all(size.width * 0.04),
            child: TextField(
              controller: _plateController,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                setState(() {
                  if (_errorMessage != null) _errorMessage = null;
                });
              },
              onSubmitted: (_) => _onSearchPressed(),
              decoration: InputDecoration(
                labelText: 'Placa del vehículo',
                hintText: 'Ej: ABC1234',
                prefixIcon: const Icon(
                  Icons.directions_car_outlined,
                  color: _colorPrimario,
                ),
                suffixIcon: _plateController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[500]),
                        onPressed: () {
                          _plateController.clear();
                          setState(() {
                            _errorMessage = null;
                            _vehicleData = null;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  vertical: size.height * 0.015,
                  horizontal: 16,
                ),
              ),
              inputFormatters: [
                UpperCaseTextFormatter(),
                LengthLimitingTextInputFormatter(7),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
              ],
            ),
          ),
          // Botón buscar
          Padding(
            padding: EdgeInsets.fromLTRB(
              size.width * 0.04,
              0,
              size.width * 0.04,
              size.width * 0.04,
            ),
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A1628), Color(0xFF000000)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF001F54).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _onSearchPressed,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search, size: 20),
                label: Text(
                  _isLoading ? 'Buscando…' : 'Buscar',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Empty state ----------------------------------------------------------
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _colorPrimario.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 48,
              color: _colorPrimario,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Consulte un vehículo',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: _colorPrimario,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingrese la placa del vehículo para consultar\nsus datos y propietario.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
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

    return Column(
      children: [
        // -- Alerta de robo --
        if (_esNoVacio(d['Robado']))
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade700,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VEHÍCULO REPORTADO',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d['Robado'].toString(),
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // -- Encabezado con placa --
        _buildResultHeader(d),
        const SizedBox(height: 14),

        // -- Stats rápidos --
        _buildQuickStats(d),
        const SizedBox(height: 14),

        // -- Sección: Identificación del Vehículo --
        _buildSection(
          icon: Icons.directions_car_filled_outlined,
          title: 'Identificación del Vehículo',
          rows: [
            _rowData(Icons.label_outline, 'Placa', d['Placa']),
            _rowData(Icons.branding_watermark_outlined, 'Marca', d['Marca']),
            _rowData(Icons.model_training_outlined, 'Modelo', d['Modelo']),
            _rowData(Icons.calendar_today_outlined, 'Año', d['Anio']),
            _rowData(Icons.palette_outlined, 'Color', d['Color']),
            _rowData(Icons.category_outlined, 'Clase', d['ClaseVehiculo']),
            _rowData(Icons.local_shipping_outlined, 'Tipo', d['TipoVehiculo']),
            _rowData(Icons.garage_outlined, 'Carrocería', d['Carroceria']),
          ],
        ),
        const SizedBox(height: 14),

        // -- Sección: Datos Técnicos --
        _buildSection(
          icon: Icons.build_outlined,
          title: 'Datos Técnicos',
          rows: [
            _rowData(Icons.speed_outlined, 'Cilindraje', d['Cilindraje']),
            _rowData(
              Icons.fitness_center_outlined,
              'Tonelaje',
              d['Tonelaje'] != null ? '${d['Tonelaje']} T' : null,
            ),
            _rowData(Icons.scale_outlined, 'Tipo Peso', d['TipoPeso']),
            _rowData(Icons.memory_outlined, 'Motor', d['Motor']),
            _rowData(Icons.qr_code_outlined, 'VIN', d['VIN']),
            _rowData(
              Icons.flag_outlined,
              'País Fabricación',
              d['PaisFabricacion'],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // -- Sección: Registro --
        _buildSection(
          icon: Icons.assignment_outlined,
          title: 'Registro',
          rows: [
            _rowData(
              Icons.swap_horiz_outlined,
              'Placa Anterior',
              d['PlacaAnterior'],
            ),
            _rowData(
              Icons.miscellaneous_services_outlined,
              'Tipo Servicio',
              d['TipoServicio'],
            ),
            _rowData(
              Icons.attach_money_outlined,
              'Avalúo Comercial',
              d['AvaluoComercial'],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // -- Sección: Matrícula (PCIR) --
        _buildSection(
          icon: Icons.verified_outlined,
          title: 'Matrícula (PCIR)',
          rows: [
            _rowData(Icons.event_outlined, 'Desde', d['InicioPcir']),
            _rowData(Icons.event_busy_outlined, 'Hasta', d['HastaPcir']),
          ],
        ),
        const SizedBox(height: 14),

        // -- Sección: Revisión Técnica --
        _buildSection(
          icon: Icons.fact_check_outlined,
          title: 'Revisión Técnica',
          rows: [
            _rowData(
              Icons.calendar_month_outlined,
              'Último Año Revisión',
              d['AnioUltimaRevision'],
            ),
            _rowData(
              Icons.event_outlined,
              'Revisión Desde',
              d['RevisionDesde'],
            ),
            _rowData(
              Icons.event_busy_outlined,
              'Revisión Hasta',
              d['RevisionHasta'],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // -- Sección: Propietario --
        _buildSection(
          icon: Icons.person_outline,
          title: 'Propietario',
          rows: [
            _rowData(Icons.person_outlined, 'Nombre', d['Propietario']),
            _rowData(Icons.fingerprint_outlined, 'Tipo Ident.', d['TipoIdent']),
            _rowData(Icons.badge_outlined, 'Cédula', d['Cedula']),
            _rowData(Icons.phone_android_outlined, 'Celular', d['Celular']),
            _rowData(Icons.email_outlined, 'Correo', d['Correo']),
            _rowData(Icons.location_on_outlined, 'Dirección', d['Direccion']),
          ],
        ),
      ],
    );
  }

  // --- Encabezado del resultado ---------------------------------------------
  Widget _buildResultHeader(Map<String, dynamic> d) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF000000)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _colorPrimario.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_car_filled,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d['Placa']?.toString().toUpperCase() ?? '-',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    d['Marca']?.toString(),
                    d['Modelo']?.toString(),
                    d['Anio']?.toString(),
                  ].where((e) => e != null && e.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_esNoVacio(d['Color']))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white30),
              ),
              child: Text(
                d['Color'].toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Stats rápidos --------------------------------------------------------
  Widget _buildQuickStats(Map<String, dynamic> d) {
    final stats = <_StatItem>[
      if (_esNoVacio(d['ClaseVehiculo']))
        _StatItem(
          Icons.category_outlined,
          'Clase',
          d['ClaseVehiculo'].toString(),
        ),
      if (_esNoVacio(d['TipoVehiculo']))
        _StatItem(
          Icons.local_shipping_outlined,
          'Tipo',
          d['TipoVehiculo'].toString(),
        ),
      if (_esNoVacio(d['Cilindraje']))
        _StatItem(
          Icons.speed_outlined,
          'Cilindraje',
          d['Cilindraje'].toString(),
        ),
      if (d['Tonelaje'] != null && d['Tonelaje'].toString() != '0')
        _StatItem(
          Icons.fitness_center_outlined,
          'Tonelaje',
          '${d['Tonelaje']} T',
        ),
    ];

    if (stats.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: List.generate(stats.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Container(width: 1, height: 36, color: _colorBorde);
          }
          final s = stats[i ~/ 2];
          return Expanded(child: _miniStat(s.icon, s.label, s.value));
        }),
      ),
    );
  }

  // --- Sección genérica con filas -------------------------------------------
  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<_RowData?> rows,
  }) {
    final visibleRows = rows
        .where((r) => r != null && _esNoVacio(r.value))
        .toList();
    if (visibleRows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header de sección
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _colorPrimario.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: _colorSecundario),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _colorPrimario,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Filas
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: visibleRows.map((r) {
                return _infoRow(r!.icon, r.label, r.value.toString());
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helpers para datos de fila -------------------------------------------
  _RowData? _rowData(IconData icon, String label, dynamic value) {
    if (!_esNoVacio(value)) return null;
    return _RowData(icon, label, value.toString());
  }

  bool _esNoVacio(dynamic value) {
    if (value == null) return false;
    final s = value.toString().trim();
    return s.isNotEmpty && s != '-' && s != 'null' && s != '0';
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

class _RowData {
  final IconData icon;
  final String label;
  final String value;
  const _RowData(this.icon, this.label, this.value);
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem(this.icon, this.label, this.value);
}

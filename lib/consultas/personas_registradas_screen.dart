import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersonasRegistradasScreen extends StatefulWidget {
  final bool canWrite;
  const PersonasRegistradasScreen({super.key, this.canWrite = false});

  @override
  State<PersonasRegistradasScreen> createState() =>
      _PersonasRegistradasScreenState();
}

class _PersonasRegistradasScreenState extends State<PersonasRegistradasScreen> {
  static const Color _primary = Color(0xFF0A1628);
  static const Color _accent = Color(0xFF1565C0);
  static const Color _fondo = Color(0xFFF0F4FF);

  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _todas = [];
  String _filtroTipo = 'todos'; // 'todos' | 'AM' | 'DC' | 'activo' | 'inactivo'

  static const int _pageSize = 30;
  int _displayCount = 30;
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> get _filtradas {
    final q = _searchController.text.trim().toLowerCase();
    return _todas.where((p) {
      // Filtro por tipo/estado
      final tipo = p['tipo_beneficiario'] as String?;
      final activo = p['activo'] as bool? ?? false;
      if (_filtroTipo == 'AM' && tipo != 'AM') return false;
      if (_filtroTipo == 'DC' && tipo != 'DC') return false;
      if (_filtroTipo == 'activo' && !activo) return false;
      if (_filtroTipo == 'inactivo' && activo) return false;

      // Filtro texto
      if (q.isEmpty) return true;
      final propietario = (p['propietario'] as String? ?? '').toLowerCase();
      final cedula = (p['cedula'] as String? ?? '').toLowerCase();
      final placa = (p['placa'] as String? ?? '').toLowerCase();
      final numero = (p['numero_documento'] as String? ?? '').toLowerCase();
      return propietario.contains(q) ||
          cedula.contains(q) ||
          placa.contains(q) ||
          numero.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchPersonas();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _displayCount = _pageSize);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      final total = _filtradas.length;
      if (_displayCount < total) {
        setState(
          () => _displayCount = (_displayCount + _pageSize).clamp(0, total),
        );
      }
    }
  }

  Future<void> _fetchPersonas() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _displayCount = _pageSize;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final uri = Uri.parse(
        'https://simert.transitoelguabo.gob.ec/api/adulto-mayor/',
      );
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Token $token',
      };
      final response = await HttpMonitorizado.get(
        uri,
        headers: headers,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          final lista = data.whereType<Map<String, dynamic>>().toList();
          if (mounted) setState(() => _todas = lista);
        } else {
          if (mounted) {
            setState(() => _errorMessage = 'Formato de respuesta inesperado.');
          }
        }
      } else {
        if (mounted) {
          setState(
            () =>
                _errorMessage = 'Error del servidor (${response.statusCode}).',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = e is TimeoutException
              ? 'La conexión tardó demasiado. Verifica tu red e intenta de nuevo.'
              : 'Error de red: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _labelTipo(String? tipo) {
    switch (tipo) {
      case 'AM':
        return 'Adulto Mayor';
      case 'DC':
        return 'Discapacitado';
      default:
        return tipo ?? '-';
    }
  }

  Color _colorTipo(String? tipo) {
    switch (tipo) {
      case 'AM':
        return const Color(0xFF2E7D32);
      case 'DC':
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFF555555);
    }
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
                    'Beneficio Adulto Mayor / Discapacidad',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Registro de beneficiarios del programa de adulto mayor y discapacidad. Permite consultar y gestionar las personas registradas.',
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Beneficio Adult. Mayor / Discap.',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1628), Color(0xFF000000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Información',
            onPressed: () => _mostrarInfo(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: _fetchPersonas,
          ),
        ],
      ),
      floatingActionButton: widget.canWrite
          ? FloatingActionButton.extended(
              heroTag: 'fab_nuevo_beneficiario',
              onPressed: _abrirFormulario,
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Nuevo'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchPanel(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Panel de búsqueda ──────────────────────────────────────────────────────
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
          // Banda superior con identidad
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
                    Icons.people_alt_rounded,
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
                      'Registro de Beneficiarios',
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
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar beneficiario',
                hintText: 'Nombre, cédula, placa…',
                prefixIcon: const Icon(Icons.search_rounded, color: _primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[500]),
                        onPressed: () => _searchController.clear(),
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
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) return _buildLoadingState();
    if (_errorMessage != null) return _buildErrorState();
    if (_todas.isEmpty) return _buildEmptyState(busqueda: false);

    final lista = _filtradas;
    final amTotal = _todas.where((p) => p['tipo_beneficiario'] == 'AM').length;
    final dcTotal = _todas.where((p) => p['tipo_beneficiario'] == 'DC').length;
    final activoTotal = _todas
        .where((p) => p['activo'] as bool? ?? false)
        .length;

    return Column(
      children: [
        // Stats tipo tab
        Container(
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${lista.length}/${_todas.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildStatTab('Todos', _todas.length, _primary, 'todos'),
                  _buildStatTab(
                    'A. Mayor',
                    amTotal,
                    const Color(0xFF2E7D32),
                    'AM',
                  ),
                  _buildStatTab(
                    'Discapac.',
                    dcTotal,
                    const Color(0xFF1565C0),
                    'DC',
                  ),
                  _buildStatTab(
                    'Activos',
                    activoTotal,
                    const Color(0xFF00897B),
                    'activo',
                  ),
                ],
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: lista.isEmpty
              ? _buildEmptyState(busqueda: true)
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _fetchPersonas,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _displayCount < lista.length
                        ? _displayCount + 1
                        : lista.length,
                    itemBuilder: (_, i) {
                      if (i >= _displayCount) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        );
                      }
                      return _buildCard(lista[i]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Estados ────────────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary, _accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_alt_rounded,
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
              color: _primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cargando beneficiarios…',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final size = MediaQuery.of(context).size;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(size.width * 0.055),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: size.width * 0.12,
                color: const Color(0xFFD32F2F),
              ),
            ),
            SizedBox(height: size.height * 0.025),
            Text(
              'Error de conexión',
              style: TextStyle(
                fontSize: size.width * 0.045,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFD32F2F),
              ),
            ),
            SizedBox(height: size.height * 0.012),
            Container(
              padding: EdgeInsets.all(size.width * 0.04),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _errorMessage ?? 'Error desconocido',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size.width * 0.035,
                  color: Colors.grey[700],
                ),
              ),
            ),
            SizedBox(height: size.height * 0.025),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton.icon(
                onPressed: _fetchPersonas,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(
                    horizontal: size.width * 0.06,
                    vertical: size.height * 0.015,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool busqueda}) {
    final size = MediaQuery.of(context).size;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(size.width * 0.06),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primary.withValues(alpha: 0.1),
                    _accent.withValues(alpha: 0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                busqueda ? Icons.search_off_rounded : Icons.people_outline,
                size: size.width * 0.12,
                color: _primary,
              ),
            ),
            SizedBox(height: size.height * 0.025),
            Text(
              busqueda ? 'Sin resultados' : 'Sin registros',
              style: TextStyle(
                fontSize: size.width * 0.045,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
            SizedBox(height: size.height * 0.01),
            Text(
              busqueda
                  ? 'No se encontraron beneficiarios con ese criterio'
                  : 'No hay beneficiarios registrados',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: size.width * 0.035,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tarjeta ────────────────────────────────────────────────────────────────
  Widget _buildCard(Map<String, dynamic> p) {
    final tipo = p['tipo_beneficiario'] as String?;
    final propietario = p['propietario'] as String? ?? '-';
    final cedula = p['cedula'] as String? ?? '-';
    final placa = (p['placa'] as String? ?? '-').toUpperCase();
    final marca = p['marca'] as String? ?? '';
    final modelo = p['modelo'] as String? ?? '';
    final activo = p['activo'] as bool? ?? false;
    final colorTipo = _colorTipo(tipo);
    final inicial = propietario.isNotEmpty ? propietario[0].toUpperCase() : '?';
    final activoColor = activo
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shadowColor: colorTipo.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorTipo.withValues(alpha: 0.3), width: 1),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _mostrarDetalle(p),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colorTipo.withValues(alpha: 0.12),
                child: Text(
                  inicial,
                  style: TextStyle(
                    color: colorTipo,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      propietario,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _primary,
                      ),
                    ),
                    Text(
                      '$cedula  ·  $placa',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (marca.isNotEmpty || modelo.isNotEmpty)
                      Text(
                        '$marca $modelo'.trim(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (tipo != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorTipo.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorTipo.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tipo == 'AM'
                                      ? Icons.elderly_rounded
                                      : Icons.accessible_rounded,
                                  size: 11,
                                  color: colorTipo,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _labelTipo(tipo),
                                  style: TextStyle(
                                    color: colorTipo,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: activoColor.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: activoColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            activo ? 'Activo' : 'Inactivo',
                            style: TextStyle(
                              color: activoColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────
  Widget _buildStatTab(String label, int count, Color color, String filtro) {
    final isSelected = _filtroTipo == filtro;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filtroTipo = filtro),
        child: Container(
          padding: const EdgeInsets.only(bottom: 10, top: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalle(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetallePersona(
        persona: p,
        canWrite: widget.canWrite,
        onEditar: widget.canWrite
            ? () {
                Navigator.pop(context);
                _abrirFormulario(persona: p);
              }
            : null,
      ),
    );
  }

  void _abrirFormulario({Map<String, dynamic>? persona}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormBeneficiario(
        persona: persona,
        existingPersonas: _todas,
        onGuardar: (datos) async {
          final id = persona?['id'] as int?;
          final (ok, errorMsg) = id != null
              ? await _actualizar(id, datos)
              : await _crear(datos);
          if (ok) {
            await _fetchPersonas();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    id != null
                        ? 'Beneficiario actualizado correctamente'
                        : 'Beneficiario registrado correctamente',
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    errorMsg.isNotEmpty
                        ? 'Error: $errorMsg'
                        : 'No se pudo guardar el beneficiario',
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
          return ok;
        },
      ),
    );
  }

  Future<(bool, String)> _crear(Map<String, dynamic> datos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Token $token',
      };
      final response = await HttpMonitorizado.post(
        Uri.parse('https://simert.transitoelguabo.gob.ec/api/adulto-mayor/'),
        headers: headers,
        body: json.encode(datos),
      ).timeout(const Duration(seconds: 30));
      debugPrint(
        '[Crear Beneficiario] status=${response.statusCode} body=${response.body}',
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return (true, '');
      }
      // Extraer mensaje de error del servidor
      String errorMsg = 'Error ${response.statusCode}';
      try {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          final msgs = <String>[];
          body.forEach((key, value) {
            if (value is List) {
              msgs.add('$key: ${value.join(", ")}');
            } else {
              msgs.add('$key: $value');
            }
          });
          if (msgs.isNotEmpty) errorMsg = msgs.join('\n');
        }
      } catch (_) {}
      return (false, errorMsg);
    } catch (e) {
      return (false, 'Error de conexión: $e');
    }
  }

  Future<(bool, String)> _actualizar(int id, Map<String, dynamic> datos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Token $token',
      };
      final response = await HttpMonitorizado.put(
        Uri.parse(
          'https://simert.transitoelguabo.gob.ec/api/adulto-mayor/$id/',
        ),
        headers: headers,
        body: json.encode(datos),
      ).timeout(const Duration(seconds: 30));
      debugPrint(
        '[Actualizar Beneficiario] status=${response.statusCode} body=${response.body}',
      );
      if (response.statusCode == 200) {
        return (true, '');
      }
      String errorMsg = 'Error ${response.statusCode}';
      try {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          final msgs = <String>[];
          body.forEach((key, value) {
            if (value is List) {
              msgs.add('$key: ${value.join(", ")}');
            } else {
              msgs.add('$key: $value');
            }
          });
          if (msgs.isNotEmpty) errorMsg = msgs.join('\n');
        }
      } catch (_) {}
      return (false, errorMsg);
    } catch (e) {
      return (false, 'Error de conexión: $e');
    }
  }
}

// ── Modal de detalle ──────────────────────────────────────────────────────────
class _DetallePersona extends StatelessWidget {
  final Map<String, dynamic> persona;
  final bool canWrite;
  final VoidCallback? onEditar;
  const _DetallePersona({
    required this.persona,
    this.canWrite = false,
    this.onEditar,
  });

  static const Color _primary = Color(0xFF0A1628);
  static const Color _accent = Color(0xFF1565C0);

  String _labelTipo(String? tipo) {
    switch (tipo) {
      case 'AM':
        return 'Adulto Mayor';
      case 'DC':
        return 'Discapacitado';
      default:
        return tipo ?? '-';
    }
  }

  String _v(dynamic v) {
    if (v == null) return '-';
    final s = v.toString().trim();
    return s.isEmpty ? '-' : s;
  }

  String _formatFecha(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _formatFechaNac(dynamic val) {
    if (val == null) return '-';
    final s = val.toString().trim();
    if (s.isEmpty) return '-';
    // Viene como yyyy-MM-dd de la API
    final parts = s.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final tipo = persona['tipo_beneficiario'] as String?;
    final activo = persona['activo'] as bool? ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Cabecera gradiente
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primary, _accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      tipo == 'AM'
                          ? Icons.elderly_rounded
                          : Icons.accessible_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _v(persona['propietario']),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _labelTipo(tipo),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Badge activo/inactivo
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (activo ? Colors.green : Colors.red).withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      activo ? 'Activo' : 'Inactivo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Contenido
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [
                  _SectionLabel(label: 'Datos personales'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Cédula / Doc.',
                    value: _v(persona['cedula']),
                  ),
                  _InfoRow(
                    icon: Icons.numbers_outlined,
                    label: 'N° Documento',
                    value: _v(persona['numero_documento']),
                  ),
                  _InfoRow(
                    icon: Icons.article_outlined,
                    label: 'Tipo ident.',
                    value: _v(persona['tipo_ident']),
                  ),
                  _InfoRow(
                    icon: Icons.cake_outlined,
                    label: 'Fecha nacimiento',
                    value: _formatFechaNac(persona['fecha_nacimiento']),
                  ),
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Correo',
                    value: _v(persona['correo']),
                  ),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Celular',
                    value: _v(persona['celular']),
                  ),
                  _InfoRow(
                    icon: Icons.home_outlined,
                    label: 'Dirección',
                    value: _v(persona['direccion']),
                  ),
                  if (tipo == 'DC')
                    _InfoRow(
                      icon: Icons.accessible_rounded,
                      label: '% Discapacidad',
                      value: _v(persona['porcentaje_discapacidad']),
                    ),
                  const SizedBox(height: 12),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F4FF),
                  ),
                  const SizedBox(height: 12),
                  _SectionLabel(label: 'Vehículo'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.directions_car_outlined,
                    label: 'Placa',
                    value: _v(persona['placa']),
                    highlight: true,
                  ),
                  _InfoRow(
                    icon: Icons.branding_watermark_outlined,
                    label: 'Marca',
                    value: _v(persona['marca']),
                  ),
                  _InfoRow(
                    icon: Icons.model_training_outlined,
                    label: 'Modelo',
                    value: _v(persona['modelo']),
                  ),
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Año',
                    value: _v(persona['anio']),
                  ),
                  _InfoRow(
                    icon: Icons.color_lens_outlined,
                    label: 'Color',
                    value: _v(persona['color']),
                  ),
                  _InfoRow(
                    icon: Icons.settings_outlined,
                    label: 'Cilindraje',
                    value: _v(persona['cilindraje']),
                  ),
                  _InfoRow(
                    icon: Icons.scale_outlined,
                    label: 'Tonelaje',
                    value: _v(persona['tonelaje']),
                  ),
                  _InfoRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Tipo servicio',
                    value: _v(persona['tipo_servicio']),
                  ),
                  _InfoRow(
                    icon: Icons.attach_money_outlined,
                    label: 'Avalúo',
                    value: _v(persona['avaluo_comercial']),
                  ),
                  const SizedBox(height: 12),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F4FF),
                  ),
                  const SizedBox(height: 12),
                  _SectionLabel(label: 'Vigencia PCIR'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.event_available_outlined,
                    label: 'Inicio',
                    value: _v(persona['inicio_pcir']),
                  ),
                  _InfoRow(
                    icon: Icons.event_busy_outlined,
                    label: 'Hasta',
                    value: _v(persona['hasta_pcir']),
                  ),
                  const SizedBox(height: 12),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F4FF),
                  ),
                  const SizedBox(height: 12),
                  _SectionLabel(label: 'Registro'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.app_registration_outlined,
                    label: 'Fecha registro',
                    value: _formatFecha(persona['fecha_registro'] as String?),
                  ),
                  _InfoRow(
                    icon: Icons.update_outlined,
                    label: 'Última actualización',
                    value: _formatFecha(
                      persona['fecha_actualizacion'] as String?,
                    ),
                  ),
                  if ((_v(persona['observaciones'])) != '-')
                    _InfoRow(
                      icon: Icons.info_outline,
                      label: 'Observaciones',
                      value: _v(persona['observaciones']),
                      italic: true,
                    ),
                  if (canWrite && onEditar != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onEditar,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Editar beneficiario'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets compartidos ────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A1628), Color(0xFF000000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A1628),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  final bool italic;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    if (value == '-') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF1565C0)),
          const SizedBox(width: 7),
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: highlight ? const Color(0xFF0A1628) : Colors.grey[800],
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Formulario registro / edición ------------------------------------------
class _FormBeneficiario extends StatefulWidget {
  final Map<String, dynamic>? persona;
  final List<Map<String, dynamic>> existingPersonas;
  final Future<bool> Function(Map<String, dynamic>) onGuardar;
  const _FormBeneficiario({
    this.persona,
    this.existingPersonas = const [],
    required this.onGuardar,
  });

  @override
  State<_FormBeneficiario> createState() => _FormBeneficiarioState();
}

class _FormBeneficiarioState extends State<_FormBeneficiario> {
  static const Color _primary = Color(0xFF0A1628);
  static const Color _accent = Color(0xFF1565C0);

  final _formKey = GlobalKey<FormState>();
  bool _guardando = false;
  bool _buscandoVehiculo = false;

  // Extras del webservice (no editables en formulario)
  String? _cilindraje;
  String? _tonelaje;
  String? _tipoServicio;
  String? _tipoPeso;
  String? _avaluoComercial;
  String? _inicioPcir;
  String? _hastaPcir;

  final _propietarioCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _numDocCtrl = TextEditingController();
  String _tipoIdent = 'CED';
  final _fechaNacCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _celularCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _discapCtrl = TextEditingController();
  final _placaCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _anioCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _observCtrl = TextEditingController();

  // Webservice cargado
  bool _vehiculoCargado = false;
  bool _robado = false;

  String _tipoBenef = 'AM';
  bool _activo = true;

  @override
  void initState() {
    super.initState();
    final p = widget.persona;
    if (p != null) {
      _tipoBenef = p['tipo_beneficiario'] as String? ?? 'AM';
      _propietarioCtrl.text = (p['propietario'] as String? ?? '').toUpperCase();
      _cedulaCtrl.text = (p['cedula'] as String? ?? '').toUpperCase();
      _numDocCtrl.text = (p['numero_documento'] as String? ?? '').toUpperCase();
      _tipoIdent = _nonEmpty(p['tipo_ident']) ?? 'CED';
      _fechaNacCtrl.text = _isoToDmy(p['fecha_nacimiento'] as String? ?? '');
      _correoCtrl.text = p['correo'] as String? ?? '';
      _celularCtrl.text = p['celular'] as String? ?? '';
      _direccionCtrl.text = (p['direccion'] as String? ?? '').toUpperCase();
      _discapCtrl.text = (p['porcentaje_discapacidad'] ?? '').toString();
      _placaCtrl.text = (p['placa'] as String? ?? '').toUpperCase();
      _marcaCtrl.text = (p['marca'] as String? ?? '').toUpperCase();
      _modeloCtrl.text = (p['modelo'] as String? ?? '').toUpperCase();
      _anioCtrl.text = (p['anio'] ?? '').toString();
      _colorCtrl.text = (p['color'] as String? ?? '').toUpperCase();
      _observCtrl.text = (p['observaciones'] as String? ?? '').toUpperCase();
      final rawActivo = p['activo'];
      _activo = rawActivo is bool
          ? rawActivo
          : (rawActivo?.toString().toLowerCase() == 'true' ||
                rawActivo?.toString() == '1');
      final rawRobado = p['robado'];
      _robado = rawRobado is bool
          ? rawRobado
          : (rawRobado?.toString().toLowerCase() == 'si' ||
                rawRobado?.toString().toLowerCase() == 'sí' ||
                rawRobado?.toString().toLowerCase() == 'true' ||
                rawRobado?.toString() == '1');
      // Preservar campos del webservice al editar
      _cilindraje = _nonEmpty(p['cilindraje']);
      _tonelaje = _nonEmpty(p['tonelaje']?.toString());
      _tipoServicio = _nonEmpty(p['tipo_servicio']);
      _tipoPeso = _nonEmpty(p['tipo_peso']);
      _avaluoComercial = _nonEmpty(p['avaluo_comercial']);
      _inicioPcir = _nonEmpty(p['inicio_pcir']);
      _hastaPcir = _nonEmpty(p['hasta_pcir']);
      _vehiculoCargado =
          _marcaCtrl.text.isNotEmpty || _placaCtrl.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _propietarioCtrl,
      _cedulaCtrl,
      _numDocCtrl,
      _fechaNacCtrl,
      _correoCtrl,
      _celularCtrl,
      _direccionCtrl,
      _discapCtrl,
      _placaCtrl,
      _marcaCtrl,
      _modeloCtrl,
      _anioCtrl,
      _colorCtrl,
      _observCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // -- Helpers webservice ----------------------------------------------------
  String? _nonEmpty(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return (s.isEmpty || s.toLowerCase() == 'desconocido') ? null : s;
  }

  void _fill(TextEditingController ctrl, dynamic value) {
    final s = _nonEmpty(value);
    if (s != null) ctrl.text = s;
  }

  /// Convierte yyyy-MM-dd → dd/MM/yyyy para mostrar
  String _isoToDmy(String iso) {
    if (iso.isEmpty) return '';
    final parts = iso.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return iso;
  }

  /// Convierte dd/MM/yyyy → yyyy-MM-dd para la API
  String _dmyToIso(String dmy) {
    if (dmy.isEmpty) return '';
    final parts = dmy.split('/');
    if (parts.length == 3) return '${parts[2]}-${parts[1]}-${parts[0]}';
    return dmy;
  }

  /// Parsea dd/MM/yyyy a DateTime
  DateTime? _parseDmy(String dmy) {
    if (dmy.isEmpty) return null;
    final parts = dmy.split('/');
    if (parts.length == 3) {
      return DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
    }
    return DateTime.tryParse(dmy);
  }

  Future<void> _buscarVehiculo() async {
    final placa = _placaCtrl.text.trim().toUpperCase();
    if (placa.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese la placa antes de buscar'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _buscandoVehiculo = true);
    try {
      final uri = Uri.parse(
        'https://simert.transitoelguabo.gob.ec/vehiculo_request?placa=$placa',
      );
      final response = await HttpMonitorizado.get(
        uri,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          setState(() {
            final p = data['Placa'];
            if (p != null && p.toString().trim().isNotEmpty) {
              _placaCtrl.text = p.toString().toUpperCase();
            }
            _fill(_propietarioCtrl, data['Propietario']);
            final tiRaw = _nonEmpty(data['TipoIdent'])?.toUpperCase() ?? '';
            if (tiRaw.contains('RUC')) {
              _tipoIdent = 'RUC';
            } else if (tiRaw.contains('PAS')) {
              _tipoIdent = 'PASAPORTE';
            } else {
              _tipoIdent = 'CED';
            }
            _fill(_cedulaCtrl, data['Cedula']);
            _fill(_correoCtrl, data['Correo']);
            _fill(_celularCtrl, data['Celular']);
            _fill(_direccionCtrl, data['Direccion']);
            _fill(_marcaCtrl, data['Marca']);
            _fill(_modeloCtrl, data['Modelo']);
            _fill(_anioCtrl, data['Anio']);
            _fill(_colorCtrl, data['Color']);
            // Guardar extras del webservice
            _cilindraje = _nonEmpty(data['Cilindraje']);
            _tonelaje = _nonEmpty(data['Tonelaje']?.toString());
            _tipoServicio = _nonEmpty(data['TipoServicio']);
            _tipoPeso = _nonEmpty(data['TipoPeso']);
            _avaluoComercial = _nonEmpty(data['AvaluoComercial']);
            _inicioPcir = _nonEmpty(data['InicioPcir']);
            _hastaPcir = _nonEmpty(data['HastaPcir']);
            final robadoRaw = data['Robado']?.toString().toLowerCase() ?? '';
            _robado =
                robadoRaw == 'si' ||
                robadoRaw == 'sí' ||
                robadoRaw == 'true' ||
                robadoRaw == '1';
            _vehiculoCargado = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Datos del vehículo $placa cargados'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se encontró información para la placa $placa'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La consulta tardó demasiado. Intente de nuevo.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al consultar placa: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoVehiculo = false);
    }
  }

  // -- Guardar ----------------------------------------------------------------
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar edad >= 65 para Adulto Mayor (creación y edición)
    if (_tipoBenef == 'AM') {
      final fechaTexto = _fechaNacCtrl.text.trim();
      if (fechaTexto.isEmpty) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: const Icon(
              Icons.cake_outlined,
              color: Colors.orange,
              size: 44,
            ),
            title: const Text('Fecha requerida', textAlign: TextAlign.center),
            content: const Text(
              'Debe ingresar la fecha de nacimiento para validar que el beneficiario sea adulto mayor (65 años o más).',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }
      final fechaNac = _parseDmy(fechaTexto);
      if (fechaNac != null) {
        final hoy = DateTime.now();
        int edad = hoy.year - fechaNac.year;
        if (hoy.month < fechaNac.month ||
            (hoy.month == fechaNac.month && hoy.day < fechaNac.day)) {
          edad--;
        }
        if (edad < 65) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 44,
              ),
              title: const Text('No aplica', textAlign: TextAlign.center),
              content: Text(
                'La persona tiene $edad años.\n\n'
                'El beneficio de Adulto Mayor aplica únicamente para personas de 65 años o más.',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }

    // Validar duplicados en el servidor (solo en alta)
    if (widget.persona == null) {
      final cedula = _cedulaCtrl.text.trim();
      final placa = _placaCtrl.text.trim().toUpperCase();

      // Verificar contra la API
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token') ?? '';
        final headers = <String, String>{
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Token $token',
        };
        final response = await HttpMonitorizado.get(
          Uri.parse('https://simert.transitoelguabo.gob.ec/api/adulto-mayor/'),
          headers: headers,
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final List<dynamic> registros = json.decode(response.body) is List
              ? json.decode(response.body) as List<dynamic>
              : (json.decode(response.body)['results'] as List<dynamic>? ?? []);

          final dupCedula = registros.any(
            (r) =>
                (r['cedula'] as String? ?? '').trim().toLowerCase() ==
                cedula.toLowerCase(),
          );
          if (dupCedula) {
            if (!mounted) return;
            await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                icon: const Icon(
                  Icons.person_off_rounded,
                  color: Colors.orange,
                  size: 44,
                ),
                title: const Text(
                  'Persona ya registrada',
                  textAlign: TextAlign.center,
                ),
                content: const Text(
                  'La cédula ingresada ya existe en el sistema.\n\n'
                  'El beneficio de estacionamiento tarifado es únicamente '
                  'para un vehículo por persona.',
                  textAlign: TextAlign.center,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            );
            return;
          }

          final dupPlaca = registros.any(
            (r) => (r['placa'] as String? ?? '').trim().toUpperCase() == placa,
          );
          if (dupPlaca) {
            if (!mounted) return;
            await showDialog(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                icon: const Icon(
                  Icons.directions_car_rounded,
                  color: Colors.orange,
                  size: 44,
                ),
                title: const Text(
                  'Vehículo ya registrado',
                  textAlign: TextAlign.center,
                ),
                content: Text(
                  'La placa $placa ya se encuentra registrada en el sistema.',
                  textAlign: TextAlign.center,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('[Validación duplicados] Error: $e');
        // Si falla la consulta, continuar con el registro
        // y dejar que el servidor valide
      }
    }

    setState(() => _guardando = true);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('id');
    final datos = <String, dynamic>{
      'tipo_beneficiario': _tipoBenef,
      'propietario': _propietarioCtrl.text.trim(),
      'cedula': _cedulaCtrl.text.trim(),
      'numero_documento': _numDocCtrl.text.trim(),
      'tipo_ident': _tipoIdent,
      'fecha_nacimiento': _dmyToIso(_fechaNacCtrl.text.trim()),
      'correo': _correoCtrl.text.trim(),
      'celular': _celularCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'placa': _placaCtrl.text.trim().toUpperCase(),
      'marca': _marcaCtrl.text.trim(),
      'modelo': _modeloCtrl.text.trim(),
      'anio': _anioCtrl.text.trim(),
      'color': _colorCtrl.text.trim(),
      'observaciones': _observCtrl.text.trim(),
      'activo': _activo,
      'robado': _robado ? 'SI' : '',
      'porcentaje_discapacidad':
          (_tipoBenef == 'DC' && _discapCtrl.text.isNotEmpty)
          ? _discapCtrl.text.trim()
          : '',
      'cilindraje': _cilindraje ?? '',
      'tonelaje': _tonelaje ?? '',
      'tipo_servicio': _tipoServicio ?? '',
      'tipo_peso': _tipoPeso ?? '',
      'avaluo_comercial': _avaluoComercial ?? '',
      'inicio_pcir': _inicioPcir ?? '',
      'hasta_pcir': _hastaPcir ?? '',
      'registrado_por': userId,
    };
    final ok = await widget.onGuardar(datos);
    if (mounted) setState(() => _guardando = false);
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _abrirDatePicker() async {
    final ahora = DateTime.now();
    DateTime? inicial = _parseDmy(_fechaNacCtrl.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: inicial ?? DateTime(ahora.year - 40),
      firstDate: DateTime(1920),
      lastDate: ahora,
      helpText: 'Fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked != null && mounted) {
      setState(() {
        _fechaNacCtrl.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/'
            '${picked.year.toString().padLeft(4, '0')}';
      });
    }
  }

  // Campos requeridos para calcular progreso
  static const int _totalCampos = 7;

  int _calcularProgreso() {
    int llenos = 0;
    if (_placaCtrl.text.trim().isNotEmpty) llenos++;
    if (_cedulaCtrl.text.trim().isNotEmpty) llenos++;
    if (_propietarioCtrl.text.trim().isNotEmpty) llenos++;
    if (_fechaNacCtrl.text.trim().isNotEmpty) llenos++;
    if (_marcaCtrl.text.trim().isNotEmpty) llenos++;
    if (_celularCtrl.text.trim().isNotEmpty) llenos++;
    if (_vehiculoCargado) llenos++;
    return llenos.clamp(0, _totalCampos);
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.persona != null;
    final progreso = _calcularProgreso();
    final pct = (progreso / _totalCampos * 100).round();
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── DARK HEADER ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      esEdicion
                          ? Icons.edit_note_rounded
                          : Icons.person_add_alt_1_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          esEdicion
                              ? 'Editar Beneficiario'
                              : 'Registrar Beneficiario',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _tipoBenef == 'AM'
                                ? 'Adulto Mayor'
                                : 'Persona con Discapacidad',
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── SCROLLABLE CONTENT ─────────────────────────────────
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  children: [
                    // -- Card: Búsqueda por placa ----------------------
                    _card(
                      icon: Icons.search_rounded,
                      title: 'Placa del vehículo *',
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _placaCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                textInputAction: TextInputAction.search,
                                maxLength: 7,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[A-Za-z0-9]'),
                                  ),
                                  TextInputFormatter.withFunction(
                                    (old, newVal) => newVal.copyWith(
                                      text: newVal.text.toUpperCase(),
                                      selection: newVal.selection,
                                    ),
                                  ),
                                ],
                                onFieldSubmitted: (_) => _buscarVehiculo(),
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'EJ: ABC1234',
                                  counterText: '',
                                  prefixIcon: const Icon(
                                    Icons.directions_car_outlined,
                                    color: _accent,
                                    size: 18,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDDE3F0),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDDE3F0),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: _accent,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 12,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Campo requerido';
                                  }
                                  final placa = v.trim().toUpperCase();
                                  // ABC1234 (3 letras + 4 dígitos)
                                  // AB123C  (2 letras + 3 dígitos + 1 letra)
                                  final valido = RegExp(
                                    r'^[A-Z]{3}[0-9]{4}$|^[A-Z]{2}[0-9]{3}[A-Z]$',
                                  ).hasMatch(placa);
                                  return valido
                                      ? null
                                      : 'Formato inválido (ABC1234 o AB123C)';
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _buscandoVehiculo
                                    ? null
                                    : _buscarVehiculo,
                                icon: _buscandoVehiculo
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.search_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  _buscandoVehiculo ? 'Buscando…' : 'Buscar',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_vehiculoCargado) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green.shade700,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Datos del vehículo cargados correctamente',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // -- Card: Tipo de beneficiario ----------------------
                    _card(
                      icon: Icons.badge_rounded,
                      title: 'Tipo de beneficiario',
                      children: [
                        Row(
                          children: [
                            _tipoBenefChip(
                              'AM',
                              Icons.elderly_rounded,
                              const Color(0xFF2E7D32),
                            ),
                            const SizedBox(width: 12),
                            _tipoBenefChip(
                              'DC',
                              Icons.accessible_rounded,
                              const Color(0xFF1565C0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // -- Card: Datos del titular -------------------------
                    _card(
                      icon: Icons.folder_shared_rounded,
                      title: 'Documentos habilitantes y datos del titular',
                      children: [
                        // Tipo ID en su propia fila
                        _dropdownCampo(
                          'Tipo Identificación',
                          Icons.article_outlined,
                          _tipoIdent,
                          const ['CED', 'RUC', 'PASAPORTE', 'OTRO'],
                          (v) => setState(() => _tipoIdent = v ?? 'CED'),
                        ),
                        // Cédula en su propia fila
                        _campo(
                          _cedulaCtrl,
                          'Cédula de identidad',
                          Icons.badge_outlined,
                          required: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          extraValidator: (v) {
                            if (v == null || v.isEmpty) return null;
                            if (v.length < 7) return 'Mín. 7 dígitos';
                            if (v.length > 13) return 'Máx. 13 dígitos';
                            return null;
                          },
                        ),
                        _campo(
                          _fechaNacCtrl,
                          'Fecha de nacimiento',
                          Icons.cake_outlined,
                          readOnly: true,
                          onTap: _abrirDatePicker,
                          onChanged: (_) => setState(() {}),
                        ),
                        _campo(
                          _propietarioCtrl,
                          'Nombres y Apellidos',
                          Icons.person_outline,
                          required: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _campo(
                                _correoCtrl,
                                'Correo electrónico',
                                Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textCapitalization: TextCapitalization.none,
                                extraValidator: (v) {
                                  if (v == null || v.isEmpty) return null;
                                  final re = RegExp(
                                    r'^[\w.+\-]+@[\w.\-]+\.[a-z]{2,}$',
                                    caseSensitive: false,
                                  );
                                  return re.hasMatch(v)
                                      ? null
                                      : 'Correo inválido';
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _campo(
                                _celularCtrl,
                                'Celular',
                                Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => setState(() {}),
                                extraValidator: (v) {
                                  if (v == null || v.isEmpty) return null;
                                  if (!v.startsWith('09') &&
                                      !v.startsWith('07')) {
                                    return 'Iniciar con 09/07';
                                  }
                                  if (v.length != 10) return '10 dígitos';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        _campo(
                          _direccionCtrl,
                          'Dirección',
                          Icons.home_outlined,
                        ),
                        if (_tipoBenef == 'DC')
                          _campo(
                            _discapCtrl,
                            '% Discapacidad',
                            Icons.accessible_rounded,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            extraValidator: (v) {
                              if (v == null || v.isEmpty) return null;
                              final n = int.tryParse(v);
                              if (n == null || n < 1 || n > 100) {
                                return '1 – 100';
                              }
                              return null;
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // -- Card: Datos del vehículo ------------------------
                    _card(
                      icon: Icons.directions_car_rounded,
                      title: 'Datos del vehículo',
                      subtitle: 'DATOS INFORMATIVOS DEL WEBSERVICE ANT',
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _campo(
                                _marcaCtrl,
                                'Marca',
                                Icons.branding_watermark_outlined,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _campo(
                                _modeloCtrl,
                                'Modelo',
                                Icons.model_training_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 90,
                              child: _campo(
                                _anioCtrl,
                                'Año',
                                Icons.calendar_today_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _campo(
                                _colorCtrl,
                                'Color',
                                Icons.color_lens_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoField(
                                'Cilindraje',
                                _cilindraje ?? '—',
                                Icons.speed_outlined,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _infoField(
                                'Tipo Servicio',
                                _tipoServicio ?? '—',
                                Icons.category_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoField(
                                'Avalúo Comercial (\$)',
                                _avaluoComercial ?? '—',
                                Icons.attach_money_outlined,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _infoField(
                                'Tonelaje',
                                _tonelaje ?? '—',
                                Icons.scale_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoField(
                                'Tipo Peso',
                                _tipoPeso ?? '—',
                                Icons.line_weight_rounded,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _infoField(
                                'Inicio PCIR',
                                _inicioPcir ?? '—',
                                Icons.event_available_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoField(
                                'Hasta PCIR',
                                _hastaPcir ?? '—',
                                Icons.event_busy_outlined,
                              ),
                            ),
                          ],
                        ),
                        // Robado
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text(
                              'Robado:',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF555555),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ChoiceChip(
                              label: const Text('Sí'),
                              selected: _robado,
                              selectedColor: Colors.red.shade100,
                              onSelected: (_) => setState(() => _robado = true),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('No'),
                              selected: !_robado,
                              selectedColor: Colors.green.shade100,
                              onSelected: (_) =>
                                  setState(() => _robado = false),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // -- Card: Observaciones y estado --------------------
                    _card(
                      icon: Icons.notes_rounded,
                      title: 'Observaciones',
                      children: [
                        _campo(
                          _observCtrl,
                          'Notas adicionales...',
                          Icons.info_outline,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text(
                              'Estado:',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF555555),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ChoiceChip(
                              label: const Text('Activo'),
                              selected: _activo,
                              selectedColor: Colors.green.shade100,
                              onSelected: (_) => setState(() => _activo = true),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Inactivo'),
                              selected: !_activo,
                              selectedColor: Colors.grey.shade200,
                              onSelected: (_) =>
                                  setState(() => _activo = false),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // -- Barra de progreso + botón fijo al pie -----------------
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progreso: $progreso/$_totalCampos campos',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progreso / _totalCampos,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade400),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _guardando ? null : _guardar,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_upload_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            _guardando ? 'Guardando…' : 'GUARDAR REGISTRO',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A1628),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card contenedor de sección
  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// Campo de solo lectura (datos del webservice)
  Widget _infoField(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      color: value == '—'
                          ? Colors.grey.shade400
                          : const Color(0xFF1A1A2E),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipoBenefChip(String tipo, IconData icon, Color color) {
    final selected = _tipoBenef == tipo;
    final label = tipo == 'AM' ? 'Adulto Mayor' : 'Discapacitado';
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tipoBenef = tipo),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? color : Colors.grey, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? color : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextInputAction textInputAction = TextInputAction.next,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? extraValidator,
    bool readOnly = false,
    VoidCallback? onTap,
    TextCapitalization textCapitalization = TextCapitalization.characters,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textInputAction: maxLines == 1
            ? textInputAction
            : TextInputAction.newline,
        inputFormatters: inputFormatters,
        readOnly: readOnly,
        onTap: onTap,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          prefixIcon: Icon(icon, color: _accent, size: 18),
          suffixIcon: readOnly && onTap != null
              ? const Icon(
                  Icons.calendar_month_rounded,
                  color: _accent,
                  size: 18,
                )
              : null,
          filled: true,
          fillColor: readOnly ? const Color(0xFFF0F4FF) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _accent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 12,
          ),
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) {
            return 'Campo requerido';
          }
          if (extraValidator != null) return extraValidator(v);
          return null;
        },
      ),
    );
  }

  Widget _dropdownCampo(
    String label,
    IconData icon,
    String value,
    List<String> opciones,
    ValueChanged<String?> onChanged, {
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: opciones.contains(value) ? value : opciones.first,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          prefixIcon: Icon(icon, color: _accent, size: 18),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 4,
            horizontal: 12,
          ),
        ),
        items: opciones
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: const TextStyle(fontSize: 14)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

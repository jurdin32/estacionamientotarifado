import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const String _kBaseUrl = 'https://simert.transitoelguabo.gob.ec/api/estacion/';
const String _kCacheKey = 'cache_admin_estaciones';

// ── Cache helper ─────────────────────────────────────────────────────────────
class _EstacionesCache {
  static Future<List<Map<String, dynamic>>?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final data = json.decode(raw);
      if (data is! List) return null;
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardar(List<Map<String, dynamic>> lista) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, json.encode(lista));
    } catch (_) {}
  }
}

class EstacionesAdminScreen extends StatefulWidget {
  const EstacionesAdminScreen({super.key});

  /// Llama esto desde HomeScreen después del login para pre-calentar
  /// el caché en segundo plano, sin bloquear la UI.
  static Future<void> preWarmCache({
    required String token,
    String sessionCookie = '',
  }) async {
    // Si ya hay caché, no hacer nada
    final existing = await _EstacionesCache.leer();
    if (existing != null && existing.isNotEmpty) return;
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (token.isNotEmpty) headers['Authorization'] = 'Token $token';
      if (sessionCookie.isNotEmpty) headers['Cookie'] = sessionCookie;
      final response = await http
          .get(Uri.parse(_kBaseUrl), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lista = (data is List ? data : (data['results'] ?? []) as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _EstacionesCache.guardar(lista);
      }
    } catch (_) {
      // Si falla, no pasa nada — se cargará al entrar a la pantalla
    }
  }

  @override
  State<EstacionesAdminScreen> createState() => _EstacionesAdminScreenState();
}

class _EstacionesAdminScreenState extends State<EstacionesAdminScreen> {
  static const Color _primary = Color(0xFF001F54);
  static const Color _accent = Color(0xFF5E17EB);
  static const Color _fondo = Color(0xFFF0F4FF);

  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = false;
  final bool _cargandoSilencioso = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _todas = [];
  String _filtroEstado =
      'todos'; // 'todos' | 'disponible' | 'ocupado' | 'reservado'
  String? _token;
  String _sessionCookie = '';

  List<Map<String, dynamic>> get _filtradas {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _todas.where((e) {
      final ocupado = e['estado'] as bool? ?? false;
      final dir = e['direccion'] as String? ?? '';
      final esReservado = dir.contains('(') && dir.contains(')');
      if (_filtroEstado == 'disponible' && (ocupado || esReservado)) {
        return false;
      }
      if (_filtroEstado == 'ocupado' && (!ocupado || esReservado)) return false;
      if (_filtroEstado == 'reservado' && !esReservado) return false;
      if (q.isEmpty) return true;
      final numero = (e['numero']?.toString() ?? '').toLowerCase();
      final placa = (e['placa'] as String? ?? '').toLowerCase();
      return numero.contains(q) ||
          dir.toLowerCase().contains(q) ||
          placa.contains(q);
    }).toList()..sort((a, b) {
      final na = (a['numero'] as int?) ?? 0;
      final nb = (b['numero'] as int?) ?? 0;
      return na.compareTo(nb);
    });
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
    _sessionCookie = prefs.getString('session_cookie') ?? '';
    // cache-first: mostrar datos al instante y refrescar en silencio
    final cache = await _EstacionesCache.leer();
    if (cache != null && cache.isNotEmpty) {
      if (mounted) setState(() => _todas = cache);
      _refrescarSilencioso();
    } else {
      await _fetchEstaciones();
    }
  }

  Map<String, String> get _authHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Token $_token';
    }
    if (_sessionCookie.isNotEmpty) {
      headers['Cookie'] = _sessionCookie;
    }
    return headers;
  }

  Future<void> _fetchEstaciones({bool silencioso = false}) async {
    if (silencioso) {
      // refresco silencioso: no altera _isLoading
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
    }
    try {
      final response = await http
          .get(Uri.parse(_kBaseUrl), headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lista = (data is List ? data : (data['results'] ?? []) as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        await _EstacionesCache.guardar(lista);
        if (mounted) setState(() => _todas = lista);
      } else {
        if (!silencioso && mounted) {
          setState(
            () =>
                _errorMessage = 'Error del servidor (${response.statusCode}).',
          );
        }
      }
    } on TimeoutException {
      if (!silencioso && mounted) {
        setState(
          () => _errorMessage =
              'La conexión tardó demasiado. Verifica tu red e intenta de nuevo.',
        );
      }
    } catch (e) {
      if (!silencioso && mounted) {
        setState(() => _errorMessage = 'Error de red: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refrescarSilencioso() => _fetchEstaciones(silencioso: true);

  // ── Crear rango de estaciones ────────────────────────────────────────────
  Future<void> _crearRango({
    required int desde,
    required int hasta,
    required String direccion,
    required bool estado,
  }) async {
    // Números ya registrados — se omiten silenciosamente
    final existentes = _todas
        .map((e) => e['numero'] as int?)
        .whereType<int>()
        .toSet();
    int creadas = 0;
    int omitidos = 0;
    for (int n = desde; n <= hasta; n++) {
      if (existentes.contains(n)) {
        omitidos++;
        continue;
      }
      final ok = await _crear({
        'numero': n,
        'direccion': direccion,
        'placa': '',
        'estado': estado,
      });
      if (ok) creadas++;
    }
    await _fetchEstaciones();
    if (mounted) {
      final msg = omitidos == 0
          ? '$creadas estacionamientos creados correctamente'
          : '$creadas creados, $omitidos omitidos (número ya existente)';
      _showSnack(msg, omitidos == 0 ? Colors.green : Colors.orange);
    }
  }

  // ── Crear ──────────────────────────────────────────────────────────────────
  Future<bool> _crear(Map<String, dynamic> datos) async {
    final response = await http.post(
      Uri.parse(_kBaseUrl),
      headers: _authHeaders,
      body: json.encode(datos),
    );
    return response.statusCode == 201;
  }

  // ── Actualizar ────────────────────────────────────────────────────────────
  Future<bool> _actualizar(int id, Map<String, dynamic> datos) async {
    final response = await http.put(
      Uri.parse('$_kBaseUrl$id/'),
      headers: _authHeaders,
      body: json.encode(datos),
    );
    return response.statusCode == 200;
  }

  // ── Eliminar ──────────────────────────────────────────────────────────────
  Future<bool> _eliminar(int id) async {
    final response = await http.delete(
      Uri.parse('$_kBaseUrl$id/'),
      headers: _authHeaders,
    );
    return response.statusCode == 204 || response.statusCode == 200;
  }

  // ── Diálogo crear/editar ──────────────────────────────────────────────────
  void _abrirFormulario({Map<String, dynamic>? estacion}) {
    // Números ya ocupados (excluye el propio si es edición)
    final editandoId = estacion?['id'] as int?;
    final numerosExistentes = _todas
        .where((e) => e['id'] != editandoId)
        .map((e) => e['numero'] as int?)
        .whereType<int>()
        .toSet();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioEstacion(
        estacion: estacion,
        numerosExistentes: numerosExistentes,
        onGuardar: (datos) async {
          final id = estacion?['id'] as int?;
          final ok = id != null
              ? await _actualizar(id, datos)
              : await _crear(datos);
          if (ok) {
            await _fetchEstaciones();
            if (mounted) {
              _showSnack(
                id != null
                    ? 'Estacionamiento actualizado correctamente'
                    : 'Estacionamiento creado correctamente',
                Colors.green,
              );
            }
          } else {
            if (mounted) {
              _showSnack('No se pudo guardar el estacionamiento', Colors.red);
            }
          }
          return ok;
        },
      ),
    );
  }

  void _abrirRango() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioRango(
        onCrear: (desde, hasta, direccion, estado) async {
          Navigator.pop(context);
          _showSnack(
            'Creando ${hasta - desde + 1} estacionamientos…',
            _primary,
          );
          await _crearRango(
            desde: desde,
            hasta: hasta,
            direccion: direccion,
            estado: estado,
          );
        },
      ),
    );
  }

  // ── Confirmar eliminar ────────────────────────────────────────────────────
  void _confirmarEliminar(Map<String, dynamic> estacion) {
    final id = estacion['id'] as int?;
    final num = estacion['numero']?.toString() ?? '-';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Eliminar estacionamiento',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          '¿Deseas eliminar el estacionamiento N° $num? Esta acción no se puede deshacer.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (id == null) return;
              final ok = await _eliminar(id);
              if (ok) {
                await _fetchEstaciones();
                if (mounted) {
                  _showSnack('Estacionamiento eliminado', Colors.green);
                }
              } else {
                if (mounted) {
                  _showSnack('No se pudo eliminar', Colors.red);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        title: const Text(
          'Gestión de Estacionamientos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_primary, _accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_rango',
        onPressed: _abrirRango,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.format_list_numbered_rounded),
        label: const Text('Crear rango'),
      ),
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

  Widget _buildSearchPanel() {
    final size = MediaQuery.of(context).size;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Banda identidad
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
                colors: [_primary, _accent],
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
                    Icons.local_parking_rounded,
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
                      'Administración de Estacionamientos',
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
          // Buscador
          Padding(
            padding: EdgeInsets.all(size.width * 0.04),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar estacionamiento',
                hintText: 'N°, dirección, placa…',
                prefixIcon: const Icon(Icons.search_rounded, color: _primary),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[500]),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingState();
    if (_errorMessage != null) return _buildErrorState();
    if (_todas.isEmpty) return _buildEmptyState(busqueda: false);

    final lista = _filtradas;
    final reservadosTotal = _todas.where((e) {
      final d = e['direccion'] as String? ?? '';
      return d.contains('(') && d.contains(')');
    }).length;
    final ocupadosTotal = _todas.where((e) {
      final d = e['direccion'] as String? ?? '';
      final esRes = d.contains('(') && d.contains(')');
      return !esRes && (e['estado'] as bool? ?? false);
    }).length;
    final disponiblesTotal = _todas.length - ocupadosTotal - reservadosTotal;

    return Column(
      children: [
        // Stats / filtros tipo tab
        Container(
          color: Colors.white,
          child: Column(
            children: [
              // Fila contador
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
              // Tabs
              Row(
                children: [
                  _buildStatTab('Todos', _todas.length, _primary, 'todos'),
                  _buildStatTab(
                    'Libres',
                    disponiblesTotal,
                    const Color(0xFF2E7D32),
                    'disponible',
                  ),
                  _buildStatTab(
                    'Ocupados',
                    ocupadosTotal,
                    const Color(0xFFC62828),
                    'ocupado',
                  ),
                  _buildStatTab(
                    'N/D',
                    reservadosTotal,
                    Colors.blue,
                    'reservado',
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
                  onRefresh: _fetchEstaciones,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _buildCard(lista[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> e) {
    final numero = e['numero']?.toString() ?? '-';
    final direccion = e['direccion'] as String? ?? '';
    final placa = (e['placa'] as String? ?? '').toUpperCase();
    final ocupado = e['estado'] as bool? ?? false;
    final esReservado = direccion.contains('(') && direccion.contains(')');

    final Color colorEstado = esReservado
        ? Colors.blue
        : ocupado
        ? Colors.redAccent
        : const Color(0xFF00C853);

    final String labelEstado = esReservado
        ? 'RESERVADO'
        : ocupado
        ? 'OCUPADO'
        : 'DISPONIBLE';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shadowColor: colorEstado.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: ocupado || esReservado
              ? colorEstado.withValues(alpha: 0.4)
              : Colors.grey.shade200,
          width: ocupado || esReservado ? 1.5 : 1,
        ),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrirFormulario(estacion: e),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar con número
              CircleAvatar(
                radius: 24,
                backgroundColor: colorEstado.withValues(alpha: 0.12),
                child: Text(
                  '#$numero',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: numero.length > 3 ? 10 : 12,
                    color: colorEstado,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Datos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Espacio #$numero',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (direccion.isNotEmpty)
                      Text(
                        direccion,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorEstado.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorEstado.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            labelEstado,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colorEstado,
                            ),
                          ),
                        ),
                        if (ocupado && placa.isNotEmpty && !esReservado) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              placa,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Acciones
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _confirmarEliminar(e),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTab(String label, int count, Color color, String filtro) {
    final isSelected = _filtroEstado == filtro;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filtroEstado = filtro),
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

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_primary, _accent]),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_parking_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_primary),
            strokeWidth: 3,
          ),
          const SizedBox(height: 14),
          Text(
            'Cargando estacionamientos…',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: Color(0xFFD32F2F),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Error de conexión',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD32F2F),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _errorMessage ?? 'Error desconocido',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchEstaciones,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool busqueda}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
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
                busqueda
                    ? Icons.search_off_rounded
                    : Icons.local_parking_rounded,
                size: 48,
                color: _primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              busqueda ? 'Sin resultados' : 'Sin estacionamientos',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              busqueda
                  ? 'No se encontraron estacionamientos con ese criterio'
                  : 'Aún no hay estacionamientos registrados.\nPresiona + para agregar uno o usa ⊞ para crear un rango.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formulario crear / editar ─────────────────────────────────────────────────
class _FormularioEstacion extends StatefulWidget {
  final Map<String, dynamic>? estacion;
  final Set<int> numerosExistentes;
  final Future<bool> Function(Map<String, dynamic> datos) onGuardar;

  const _FormularioEstacion({
    this.estacion,
    this.numerosExistentes = const {},
    required this.onGuardar,
  });

  @override
  State<_FormularioEstacion> createState() => _FormularioEstacionState();
}

class _FormularioEstacionState extends State<_FormularioEstacion> {
  static const Color _primary = Color(0xFF001F54);
  static const Color _accent = Color(0xFF5E17EB);

  final _formKey = GlobalKey<FormState>();
  final _numeroCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _placaCtrl = TextEditingController();
  bool _estado = false;
  bool _guardando = false;

  bool get _esEdicion => widget.estacion != null;

  @override
  void initState() {
    super.initState();
    final e = widget.estacion;
    if (e != null) {
      _numeroCtrl.text = e['numero']?.toString() ?? '';
      _direccionCtrl.text = e['direccion'] as String? ?? '';
      _placaCtrl.text = e['placa'] as String? ?? '';
      _estado = e['estado'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _direccionCtrl.dispose();
    _placaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final datos = <String, dynamic>{
      'numero': _numeroCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(_numeroCtrl.text.trim()),
      'direccion': _direccionCtrl.text.trim(),
      'placa': _placaCtrl.text.trim().toUpperCase(),
      'estado': _estado,
    };

    final ok = await widget.onGuardar(datos);
    if (mounted) {
      setState(() => _guardando = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // Cabecera
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _esEdicion
                          ? Icons.edit_rounded
                          : Icons.add_location_alt_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _esEdicion
                        ? 'Editar estacionamiento'
                        : 'Nuevo estacionamiento',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            // Formulario
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Número
                    _buildField(
                      controller: _numeroCtrl,
                      label: 'Número',
                      hint: 'Ej: 1, 42…',
                      icon: Icons.tag_rounded,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return null; // opcional
                        }
                        final n = int.tryParse(v.trim());
                        if (n == null) return 'Número inválido';
                        if (widget.numerosExistentes.contains(n)) {
                          return 'El N° $n ya está registrado';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    // Dirección
                    _buildField(
                      controller: _direccionCtrl,
                      label: 'Dirección',
                      hint: 'Ej: Av. 10 de Agosto y Olmedo',
                      icon: Icons.location_on_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'La dirección es obligatoria'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    // Placa
                    _buildField(
                      controller: _placaCtrl,
                      label: 'Placa asignada',
                      hint: 'Ej: ABC-1234',
                      icon: Icons.directions_car_outlined,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                    // Estado toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.power_settings_new_rounded,
                            color: _accent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Estado',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: _primary,
                                  ),
                                ),
                                Text(
                                  _estado ? 'Ocupado' : 'Disponible',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _estado
                                        ? const Color(0xFFC62828)
                                        : const Color(0xFF2E7D32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _estado,
                            activeColor: _accent,
                            onChanged: (v) => setState(() => _estado = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Botón guardar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _guardando
                              ? 'Guardando…'
                              : _esEdicion
                              ? 'Actualizar'
                              : 'Crear estacionamiento',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _accent, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        labelStyle: const TextStyle(color: _primary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
      ),
    );
  }
}

// ── Formulario de rango ───────────────────────────────────────────────────────
class _FormularioRango extends StatefulWidget {
  final Future<void> Function(
    int desde,
    int hasta,
    String direccion,
    bool estado,
  )
  onCrear;

  const _FormularioRango({required this.onCrear});

  @override
  State<_FormularioRango> createState() => _FormularioRangoState();
}

class _FormularioRangoState extends State<_FormularioRango> {
  static const Color _primary = Color(0xFF001F54);
  static const Color _accent = Color(0xFF5E17EB);

  final _formKey = GlobalKey<FormState>();
  final _desdeCtrl = TextEditingController();
  final _hastaCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  bool _estado = false;
  bool _procesando = false;

  int get _cantidad {
    final d = int.tryParse(_desdeCtrl.text.trim()) ?? 0;
    final h = int.tryParse(_hastaCtrl.text.trim()) ?? 0;
    if (h >= d && d > 0) return h - d + 1;
    return 0;
  }

  @override
  void dispose() {
    _desdeCtrl.dispose();
    _hastaCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);
    await widget.onCrear(
      int.parse(_desdeCtrl.text.trim()),
      int.parse(_hastaCtrl.text.trim()),
      _direccionCtrl.text.trim(),
      _estado,
    );
    if (mounted) setState(() => _procesando = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cant = _cantidad;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // Cabecera
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.format_list_numbered_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Crear rango de estacionamientos',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            // Formulario
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: _accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Se crearán todos los estacionamientos numerados '
                              'consecutivamente desde el número inicial hasta el '
                              'final, con la misma dirección y estado.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Desde — Hasta
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _desdeCtrl,
                            label: 'Desde N°',
                            hint: '1',
                            icon: Icons.first_page_rounded,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Requerido';
                              }
                              final n = int.tryParse(v.trim());
                              if (n == null || n < 1) return 'Número inválido';
                              return null;
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ),
                        Expanded(
                          child: _buildField(
                            controller: _hastaCtrl,
                            label: 'Hasta N°',
                            hint: '50',
                            icon: Icons.last_page_rounded,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Requerido';
                              }
                              final h = int.tryParse(v.trim());
                              final d =
                                  int.tryParse(_desdeCtrl.text.trim()) ?? 0;
                              if (h == null || h < 1) return 'Número inválido';
                              if (h < d) return 'Debe ser ≥ Desde';
                              if (h - d + 1 > 500) return 'Máximo 500';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    // Preview cantidad
                    if (cant > 0) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Se crearán $cant estacionamientos',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Dirección
                    _buildField(
                      controller: _direccionCtrl,
                      label: 'Dirección común',
                      hint: 'Ej: Av. 10 de Agosto',
                      icon: Icons.location_on_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'La dirección es obligatoria'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // Estado
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.power_settings_new_rounded,
                            color: _accent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Estado inicial',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: _primary,
                                  ),
                                ),
                                Text(
                                  _estado ? 'Ocupados' : 'Disponibles',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _estado
                                        ? const Color(0xFFC62828)
                                        : const Color(0xFF2E7D32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _estado,
                            activeColor: _accent,
                            onChanged: (v) => setState(() => _estado = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Botón
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_procesando || cant == 0) ? null : _crear,
                        icon: _procesando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.playlist_add_rounded, size: 18),
                        label: Text(
                          _procesando
                              ? 'Creando estacionamientos…'
                              : cant > 0
                              ? 'Crear $cant estacionamientos'
                              : 'Crear rango',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _accent, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        labelStyle: const TextStyle(color: _primary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
      ),
    );
  }
}

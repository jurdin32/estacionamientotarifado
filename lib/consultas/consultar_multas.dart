import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../snnipers/cambia_mayusculas.dart';
import '../tarjetas/models/Multa.dart';
import '../servicios/servicioTiposMultas.dart';

// Modelos de datos con manejo de nulos
class NotificacionDetalle {
  final int id;
  final Notificacion notificacion;
  final String usuario;
  final DateTime fecha;
  final double total;
  final bool estado;
  final bool procede;
  final int multa;

  NotificacionDetalle({
    required this.id,
    required this.notificacion,
    required this.usuario,
    required this.fecha,
    required this.total,
    required this.estado,
    required this.procede,
    required this.multa,
  });

  factory NotificacionDetalle.fromJson(Map<String, dynamic> json) {
    return NotificacionDetalle(
      id: json['id'] ?? 0,
      notificacion: Notificacion.fromJson(json['notificacion'] ?? {}),
      usuario: json['usuario']?.toString() ?? 'N/A',
      fecha: DateTime.parse(
        json['fecha']?.toString() ?? DateTime.now().toString(),
      ),
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      estado: json['estado'] ?? false,
      procede: json['procede'] ?? false,
      multa: json['multa'] ?? 0,
    );
  }
}

class Notificacion {
  final int id;
  final String numero;
  final DateTime fecha;
  final DateTime modificacion;
  final DateTime fechaEmision;
  final String ubicacion;
  final String placa;
  final String cedula;
  final String nombres;
  final String? apellidos;
  final String telefono;
  final String direccion;
  final String email;
  final bool estado;
  final bool anulado;
  final String? observacion;
  final String numeroComprobante;
  final bool eliminado;
  final bool impugnacion;
  final DateTime? fechaResolucion;
  final bool impugnacionFavorable;
  final bool impugnacionNoFavorable;
  final String? observacionImpugnacion;
  final String? resolucion;
  final String? numeroResolucion;
  final int usuario;

  Notificacion({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.modificacion,
    required this.fechaEmision,
    required this.ubicacion,
    required this.placa,
    required this.cedula,
    required this.nombres,
    this.apellidos,
    required this.telefono,
    required this.direccion,
    required this.email,
    required this.estado,
    required this.anulado,
    this.observacion,
    required this.numeroComprobante,
    required this.eliminado,
    required this.impugnacion,
    this.fechaResolucion,
    required this.impugnacionFavorable,
    required this.impugnacionNoFavorable,
    this.observacionImpugnacion,
    this.resolucion,
    this.numeroResolucion,
    required this.usuario,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    return Notificacion(
      id: json['id'] ?? 0,
      numero: json['numero']?.toString() ?? 'N/A',
      fecha: DateTime.parse(
        json['fecha']?.toString() ?? DateTime.now().toString(),
      ),
      modificacion: DateTime.parse(
        json['modificacion']?.toString() ?? DateTime.now().toString(),
      ),
      fechaEmision: DateTime.parse(
        json['fecha_emision']?.toString() ?? DateTime.now().toString(),
      ),
      ubicacion: json['ubicacion']?.toString() ?? 'Ubicación no disponible',
      placa: json['placa']?.toString() ?? 'N/A',
      cedula: json['cedula']?.toString() ?? 'N/A',
      nombres: json['nombres']?.toString() ?? 'Nombre no disponible',
      apellidos: json['apellidos']?.toString(),
      telefono: json['telefono']?.toString() ?? 'N/A',
      direccion: json['direccion']?.toString() ?? 'Dirección no disponible',
      email: json['email']?.toString() ?? 'N/A',
      estado: json['estado'] ?? false,
      anulado: json['anulado'] ?? false,
      observacion: json['observacion']?.toString(),
      numeroComprobante: json['numero_comprobante']?.toString() ?? 'N/A',
      eliminado: json['eliminado'] ?? false,
      impugnacion: json['impugnacion'] ?? false,
      fechaResolucion: json['fecha_resolucion'] != null
          ? DateTime.tryParse(json['fecha_resolucion']?.toString() ?? '')
          : null,
      impugnacionFavorable: json['impugnacion_favorable'] ?? false,
      impugnacionNoFavorable: json['impugnacion_no_favorable'] ?? false,
      observacionImpugnacion: json['observacion_impugnacion']?.toString(),
      resolucion: json['resolucion']?.toString(),
      numeroResolucion: json['numero_resolucion']?.toString(),
      usuario: json['usuario'] ?? 0,
    );
  }
}

// Servicio de API con mejor manejo de errores
class NotificacionService {
  static const String _baseUrl = 'https://simert.transitoelguabo.gob.ec/api';

  final http.Client client;

  NotificacionService({http.Client? client}) : client = client ?? http.Client();

  Future<List<NotificacionDetalle>> getNotificaciones({
    String? notificacionId,
    String? cedula,
    String? placa,
    String? username,
    String? fechaInicio,
    String? fechaFin,
  }) async {
    try {
      final Map<String, String> queryParams = {};

      if (notificacionId != null && notificacionId.isNotEmpty) {
        queryParams['notificacion__id'] = notificacionId;
      }
      if (cedula != null && cedula.isNotEmpty) {
        queryParams['notificacion__cedula'] = cedula;
      }
      if (placa != null && placa.isNotEmpty) {
        queryParams['notificacion__placa'] = placa;
      }
      if (username != null && username.isNotEmpty) {
        queryParams['notificacion__usuario__username'] = username;
      }
      if (fechaInicio != null && fechaInicio.isNotEmpty) {
        queryParams['fecha_inicio'] = fechaInicio;
      }
      if (fechaFin != null && fechaFin.isNotEmpty) {
        queryParams['fecha_fin'] = fechaFin;
      }

      final uri = Uri.parse(
        '$_baseUrl/notificaciondetalle/',
      ).replace(queryParameters: queryParams);

      final response = await client.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(
          utf8.decode(response.bodyBytes),
        );

        return jsonResponse
            .map((json) => NotificacionDetalle.fromJson(json))
            .toList();
      } else {
        throw Exception('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  Future<List<NotificacionDetalle>> getNotificacionesPorPlaca(String placa) {
    return getNotificaciones(placa: placa);
  }

  Future<List<NotificacionDetalle>> getNotificacionesPorCedula(String cedula) {
    return getNotificaciones(cedula: cedula);
  }

  void dispose() {
    client.close();
  }
}

// Provider para el estado
class NotificacionProvider with ChangeNotifier {
  final NotificacionService _service;
  List<NotificacionDetalle> _notificaciones = [];
  bool _loading = false;
  String? _error;

  NotificacionProvider({NotificacionService? service})
    : _service = service ?? NotificacionService();

  List<NotificacionDetalle> get notificaciones => _notificaciones;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> buscarNotificaciones({
    String? notificacionId,
    String? cedula,
    String? placa,
    String? username,
    String? fechaInicio,
    String? fechaFin,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _notificaciones =
          (await _service.getNotificaciones(
                notificacionId: notificacionId,
                cedula: cedula,
                placa: placa,
                username: username,
                fechaInicio: fechaInicio,
                fechaFin: fechaFin,
              ))
              .where(
                (n) => !n.notificacion.eliminado && !n.notificacion.anulado,
              )
              .toList();
    } catch (e) {
      _error = e.toString();
      _notificaciones = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> buscarPorPlaca(String placa) async {
    await buscarNotificaciones(placa: placa);
  }

  Future<void> buscarPorCedula(String cedula) async {
    await buscarNotificaciones(cedula: cedula);
  }

  void limpiarResultados() {
    _notificaciones.clear();
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

// Pantalla principal
class ConsultaNotificacionesScreen extends StatefulWidget {
  const ConsultaNotificacionesScreen({super.key});

  @override
  State<ConsultaNotificacionesScreen> createState() =>
      _ConsultaNotificacionesScreenState();
}

class _ConsultaNotificacionesScreenState
    extends State<ConsultaNotificacionesScreen> {
  final _provider = NotificacionProvider();
  final _placaController = TextEditingController();
  final _cedulaController = TextEditingController();
  String _tipoBusqueda = 'placa';
  bool _hasBuscado = false;
  String _filtroEstado = 'todos';
  Map<int, Multa> _multasMap = {};

  @override
  void initState() {
    super.initState();
    _cargarMultas();
  }

  Future<void> _cargarMultas() async {
    final lista = await obtenerMultasGuardadas();
    if (lista.isNotEmpty) {
      setState(() {
        _multasMap = {for (final m in lista) m.id: m};
      });
    } else {
      // Si no hay caché, intentar desde la API
      try {
        final lista2 = await fetchMultas();
        if (mounted) {
          setState(() {
            _multasMap = {for (final m in lista2) m.id: m};
          });
        }
      } catch (_) {}
    }
  }

  List<NotificacionDetalle> get _filtradas {
    final todas = _provider.notificaciones;
    return switch (_filtroEstado) {
      'pendientes' =>
        todas
            .where((n) => !n.notificacion.estado && !n.notificacion.impugnacion)
            .toList(),
      'pagados' => todas.where((n) => n.notificacion.estado).toList(),
      'impugnados' => todas.where((n) => n.notificacion.impugnacion).toList(),
      _ => todas,
    };
  }

  @override
  void dispose() {
    _provider.dispose();
    _placaController.dispose();
    _cedulaController.dispose();
    super.dispose();
  }

  void _buscar() {
    // Ocultar teclado
    FocusScope.of(context).unfocus();

    if (_tipoBusqueda == 'placa' && _placaController.text.isNotEmpty) {
      setState(() {
        _hasBuscado = true;
        _filtroEstado = 'todos';
      });
      _provider.buscarPorPlaca(_placaController.text.trim().toUpperCase());
    } else if (_tipoBusqueda == 'cedula' && _cedulaController.text.isNotEmpty) {
      setState(() {
        _hasBuscado = true;
        _filtroEstado = 'todos';
      });
      _provider.buscarPorCedula(_cedulaController.text.trim());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Por favor ingrese un valor para buscar'),
          backgroundColor: Colors.orange[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _limpiar() {
    _placaController.clear();
    _cedulaController.clear();
    _provider.limpiarResultados();
    FocusScope.of(context).unfocus();
    setState(() {
      _hasBuscado = false;
      _filtroEstado = 'todos';
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text(
          'Consulta de Multas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF001F54),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Información',
            onPressed: () => _mostrarInformacion(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchPanel(),
            Expanded(child: _buildResults()),
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
                colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
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
                    Icons.gavel,
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
                      'Sistema de Multas Electrónicas',
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

          // Contenido de búsqueda
          Padding(
            padding: EdgeInsets.all(size.width * 0.04),
            child: Column(
              children: [
                // Selector de tipo
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSearchTypeButton(
                          'placa',
                          'Por Placa',
                          Icons.directions_car,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildSearchTypeButton(
                          'cedula',
                          'Por Cédula',
                          Icons.badge,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: size.height * 0.018),

                // Campo de búsqueda
                TextField(
                  controller: _tipoBusqueda == 'placa'
                      ? _placaController
                      : _cedulaController,
                  decoration: InputDecoration(
                    labelText: _tipoBusqueda == 'placa'
                        ? 'Placa del vehículo'
                        : 'Cédula del conductor',
                    hintText: _tipoBusqueda == 'placa'
                        ? 'Ej: TBG7906'
                        : 'Ej: 1805177035',
                    prefixIcon: Icon(
                      _tipoBusqueda == 'placa'
                          ? Icons.directions_car
                          : Icons.badge,
                      color: const Color(0xFF001F54),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey[500]),
                      onPressed: () {
                        if (_tipoBusqueda == 'placa') {
                          _placaController.clear();
                        } else {
                          _cedulaController.clear();
                        }
                      },
                    ),
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
                  textCapitalization: _tipoBusqueda == 'placa'
                      ? TextCapitalization.characters
                      : TextCapitalization.none,
                  inputFormatters: _tipoBusqueda == 'placa'
                      ? [UpperCaseTextFormatter()]
                      : null,
                  onSubmitted: (_) => _buscar(),
                ),
                SizedBox(height: size.height * 0.015),

                // Botones
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF001F54,
                              ).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _buscar,
                          icon: const Icon(Icons.search, size: 20),
                          label: const Text(
                            'Buscar',
                            style: TextStyle(fontWeight: FontWeight.w600),
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
                    SizedBox(width: size.width * 0.03),
                    SizedBox(
                      width: 90,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _limpiar,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade400),
                          foregroundColor: Colors.grey.shade700,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.clear_all, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Limpiar',
                              style: TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
    );
  }

  Widget _buildSearchTypeButton(String value, String text, IconData icon) {
    const primary = Color(0xFF001F54);
    final isSelected = _tipoBusqueda == value;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _tipoBusqueda = value);
            if (value == 'placa') {
              _placaController.clear();
            } else {
              _cedulaController.clear();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? primary : Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? primary : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, child) {
        if (_provider.loading) return _buildLoadingState();
        if (_provider.error != null) return _buildErrorState();
        if (!_hasBuscado) return _buildInitialState();
        if (_provider.notificaciones.isEmpty) return _buildEmptyState();
        return _buildResultsList();
      },
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
              gradient: LinearGradient(
                colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.gavel, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text(
            'SIMERT',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001F54),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Buscando notificaciones...',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF5E17EB),
              ),
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                _provider.error?.replaceAll('Exception: ', '') ??
                    'Error desconocido',
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
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _buscar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar búsqueda'),
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

  Widget _buildEmptyState() {
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
                    const Color(0xFF001F54).withValues(alpha: 0.1),
                    const Color(0xFF5E17EB).withValues(alpha: 0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: size.width * 0.12,
                color: const Color(0xFF001F54),
              ),
            ),
            SizedBox(height: size.height * 0.025),
            Text(
              'Sin resultados',
              style: TextStyle(
                fontSize: size.width * 0.045,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF001F54),
              ),
            ),
            SizedBox(height: size.height * 0.01),
            Text(
              'No se encontraron notificaciones para los datos ingresados',
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

  Widget _buildResultsList() {
    final size = MediaQuery.of(context).size;
    final todas = _provider.notificaciones;
    final pendientes = todas
        .where((n) => !n.notificacion.estado && !n.notificacion.impugnacion)
        .toList();
    final pagadas = todas.where((n) => n.notificacion.estado).toList();
    final impugnadas = todas.where((n) => n.notificacion.impugnacion).toList();
    pendientes.fold(0.0, (sum, n) => sum + n.total);
    final lista = _filtradas;

    return Column(
      children: [
        // Stats tipo tab
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${lista.length}/${todas.length}',
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
                  _buildStatTab(
                    'Todos',
                    todas.length,
                    const Color(0xFF001F54),
                    'todos',
                  ),
                  _buildStatTab(
                    'Pendientes',
                    pendientes.length,
                    const Color(0xFFE65100),
                    'pendientes',
                  ),
                  _buildStatTab(
                    'Pagadas',
                    pagadas.length,
                    const Color(0xFF2E7D32),
                    'pagados',
                  ),
                  _buildStatTab(
                    'Impugnadas',
                    impugnadas.length,
                    const Color(0xFF6A1B9A),
                    'impugnados',
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Text(
                    'Ninguna notificación en este filtro',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: size.width * 0.038,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(size.width * 0.04),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    return _NotificacionCard(
                      notificacion: lista[index],
                      formatDate: _formatDate,
                      formatDateTime: _formatDateTime,
                      multasMap: _multasMap,
                    );
                  },
                ),
        ),
      ],
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

  Widget _buildInitialState() {
    final size = MediaQuery.of(context).size;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(size.width * 0.07),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.manage_search_rounded,
                size: size.width * 0.12,
                color: Colors.white,
              ),
            ),
            SizedBox(height: size.height * 0.03),
            Text(
              'Consulte sus notificaciones',
              style: TextStyle(
                fontSize: size.width * 0.047,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF001F54),
              ),
            ),
            SizedBox(height: size.height * 0.012),
            Text(
              'Ingrese la placa del vehículo o la cédula del conductor para consultar notificaciones de tránsito.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: size.width * 0.035,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            SizedBox(height: size.height * 0.03),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTipChip(Icons.directions_car_outlined, 'Por placa'),
                SizedBox(width: size.width * 0.03),
                _buildTipChip(Icons.badge_outlined, 'Por cédula'),
              ],
            ),
            SizedBox(height: size.height * 0.025),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.arrow_upward_rounded,
                  size: 14,
                  color: Color(0xFF5E17EB),
                ),
                const SizedBox(width: 4),
                Text(
                  'Use el buscador de arriba',
                  style: TextStyle(
                    fontSize: size.width * 0.033,
                    color: const Color(0xFF5E17EB),
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

  Widget _buildTipChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF001F54).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF001F54).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF001F54)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF001F54),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarInformacion(BuildContext context) {
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
                  colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
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
                    'Consultor de Notificaciones SIMERT',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Este sistema le permite consultar las notificaciones de tránsito emitidas por la Dirección de Tránsito.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Puede buscar por número de placa del vehículo o por cédula del conductor.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(
                          color: Color(0xFF001F54),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
}

// Widget para mostrar cada notificación
class _NotificacionCard extends StatelessWidget {
  final NotificacionDetalle notificacion;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatDateTime;
  final Map<int, Multa> multasMap;

  const _NotificacionCard({
    required this.notificacion,
    required this.formatDate,
    required this.formatDateTime,
    required this.multasMap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF001F54);
    final bool impugnacion = notificacion.notificacion.impugnacion;
    // notificacion.notificacion.estado: true=PAGADO, false=IMPAGO
    final bool pagado = notificacion.notificacion.estado;

    // Prioridad: impugnación > pagado > pendiente
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;
    if (impugnacion) {
      statusColor = const Color(0xFF7B1FA2);
      statusText = 'EN IMPUGNACIÓN';
      statusIcon = Icons.balance_rounded;
    } else if (pagado) {
      statusColor = const Color(0xFF00C853);
      statusText = 'PAGADO';
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = const Color(0xFFFF9800);
      statusText = 'PENDIENTE';
      statusIcon = Icons.hourglass_empty_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera con gradiente
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notificacion.notificacion.numero,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Cuerpo
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fecha de emisión + monto
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Emitida: ${formatDate(notificacion.notificacion.fechaEmision)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '\$${notificacion.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F4FF),
                  ),
                  const SizedBox(height: 10),

                  // Banner de impugnación
                  if (impugnacion) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B1FA2).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(
                            0xFF7B1FA2,
                          ).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.balance_rounded,
                            size: 16,
                            color: Color(0xFF7B1FA2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              notificacion
                                          .notificacion
                                          .observacionImpugnacion
                                          ?.isNotEmpty ==
                                      true
                                  ? 'Impugnación: ${notificacion.notificacion.observacionImpugnacion}'
                                  : 'Esta notificación se encuentra en proceso de impugnación.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7B1FA2),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── DATOS DEL INFRACTOR ──────────────────────────────
                  _SectionLabel(label: 'Datos del infractor'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Nombre',
                    value: [
                      notificacion.notificacion.nombres,
                      if (notificacion.notificacion.apellidos?.isNotEmpty ==
                          true)
                        notificacion.notificacion.apellidos!,
                    ].join(' '),
                    hide:
                        notificacion.notificacion.nombres.isEmpty ||
                        notificacion.notificacion.nombres ==
                            'Nombre no disponible',
                  ),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Cédula',
                    value: notificacion.notificacion.cedula,
                    hide:
                        notificacion.notificacion.cedula.isEmpty ||
                        notificacion.notificacion.cedula == 'N/A',
                  ),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Teléfono',
                    value: notificacion.notificacion.telefono,
                    hide:
                        notificacion.notificacion.telefono.isEmpty ||
                        notificacion.notificacion.telefono == 'N/A',
                  ),
                  _InfoRow(
                    icon: Icons.home_outlined,
                    label: 'Dirección',
                    value: notificacion.notificacion.direccion,
                    hide:
                        notificacion.notificacion.direccion.isEmpty ||
                        notificacion.notificacion.direccion ==
                            'Dirección no disponible',
                  ),

                  const SizedBox(height: 10),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F4FF),
                  ),
                  const SizedBox(height: 10),

                  // ── DETALLE DE LA INFRACCIÓN ─────────────────────────
                  _SectionLabel(label: 'Detalle de la infracción'),
                  const SizedBox(height: 8),
                  if (multasMap.containsKey(notificacion.multa)) ...[
                    _InfoRow(
                      icon: Icons.gavel_rounded,
                      label: 'Tipo',
                      value: multasMap[notificacion.multa]!.tipo,
                      highlight: true,
                      hide: multasMap[notificacion.multa]!.tipo.isEmpty,
                    ),
                    _InfoRow(
                      icon: Icons.description_outlined,
                      label: 'Infracción',
                      value: multasMap[notificacion.multa]!.detalleMulta,
                      hide: multasMap[notificacion.multa]!.detalleMulta.isEmpty,
                    ),
                  ],
                  _InfoRow(
                    icon: Icons.directions_car_outlined,
                    label: 'Placa',
                    value: notificacion.notificacion.placa,
                    highlight: true,
                    hide:
                        notificacion.notificacion.placa.isEmpty ||
                        notificacion.notificacion.placa == 'N/A',
                  ),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Ubicación',
                    value: notificacion.notificacion.ubicacion,
                    hide:
                        notificacion.notificacion.ubicacion.isEmpty ||
                        notificacion.notificacion.ubicacion ==
                            'Ubicación no disponible',
                  ),
                  _InfoRow(
                    icon: Icons.receipt_outlined,
                    label: 'N° Comprobante',
                    value: notificacion.notificacion.numeroComprobante,
                    hide:
                        notificacion.notificacion.numeroComprobante.isEmpty ||
                        notificacion.notificacion.numeroComprobante == 'N/A',
                  ),
                  _InfoRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Emitida por',
                    value: notificacion.usuario,
                    hide:
                        notificacion.usuario.isEmpty ||
                        notificacion.usuario == 'N/A',
                  ),
                  if (notificacion.notificacion.observacion?.isNotEmpty == true)
                    _InfoRow(
                      icon: Icons.info_outline,
                      label: 'Observación',
                      value: notificacion.notificacion.observacion!,
                      italic: true,
                    ),

                  const SizedBox(height: 10),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF0F4FF),
                  ),
                  const SizedBox(height: 10),

                  // Botón imprimir informe
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://simert.transitoelguabo.gob.ec/multas/?id=${notificacion.id}',
                        );
                        try {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text(
                        'Ver / Imprimir informe',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF001F54),
                        side: const BorderSide(
                          color: Color(0xFF001F54),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
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
}

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
              colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
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
            color: Color(0xFF001F54),
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
  final bool hide;
  final bool highlight;
  final bool italic;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.hide = false,
    this.highlight = false,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    if (hide) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF5E17EB)),
          const SizedBox(width: 7),
          SizedBox(
            width: 110,
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
                color: highlight ? const Color(0xFF001F54) : Colors.grey[800],
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

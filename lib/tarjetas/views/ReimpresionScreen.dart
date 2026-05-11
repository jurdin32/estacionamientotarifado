import 'dart:convert';
import 'dart:io';

import 'package:estacionamientotarifado/core/colores.dart';
import 'package:estacionamientotarifado/servicios/gestorImpresora.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart';
import 'package:estacionamientotarifado/servicios/servicioTiposMultas.dart';
import 'package:estacionamientotarifado/shared/widgets/campo_busqueda_app.dart';
import 'package:estacionamientotarifado/shared/widgets/estado_carga_app.dart';
import 'package:estacionamientotarifado/shared/widgets/tarjeta_lista_app.dart';
import 'package:estacionamientotarifado/tarjetas/models/Multa.dart';
import 'package:estacionamientotarifado/tarjetas/views/WidgetsImpresora.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

class ReimpresionScreen extends StatefulWidget {
  const ReimpresionScreen({super.key});

  @override
  State<ReimpresionScreen> createState() => _ReimpresionScreenState();
}

class _ReimpresionScreenState extends State<ReimpresionScreen> {
  // ─── Design tokens ────────────────────────────────────────────────────────
  static const Color _colorPrimario = Color(0xFF0A1628);
  static const Color _colorFondo = Color(0xFFF0F4FF);
  static const Color _colorTexto = Color(0xFF333333);

  // ─── State ────────────────────────────────────────────────────────────────
  final GestorImpresora _gestorImpresora = GestorImpresora();
  final NotificacionService _svc = NotificacionService();

  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  String? _error;
  String _operador = '';
  int _usuarioId = 0;
  bool _esSuperuser = false;
  final Map<int, String> _usuariosPorId = {};
  List<Multa> _multasCache = [];

  // Filtro de búsqueda
  String _textoBusqueda = '';
  final TextEditingController _busquedaCtrl = TextEditingController();

  // Tracks which item is currently being processed (print/PDF)
  int? _procesandoId;

  List<Map<String, dynamic>> get _itemsFiltrados {
    List<Map<String, dynamic>> lista;
    if (_textoBusqueda.isEmpty) {
      lista = List.of(_items);
    } else {
      final q = _textoBusqueda.toLowerCase();
      lista = _items.where((item) {
        return (item['placa'] as String).toLowerCase().contains(q) ||
            (item['tipoMulta'] as String).toLowerCase().contains(q) ||
            (item['comprobante'] as String).toLowerCase().contains(q) ||
            (item['nombrePersona'] ?? '').toString().toLowerCase().contains(
              q,
            ) ||
            (item['cedula'] ?? '').toString().toLowerCase().contains(q) ||
            (item['usuarioEmisor'] ?? '').toString().toLowerCase().contains(
              q,
            ) ||
            (item['marca'] ?? '').toString().toLowerCase().contains(q) ||
            (item['modelo'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }
    lista.sort((a, b) {
      try {
        return DateTime.parse(
          b['fechaEmision'] as String,
        ).compareTo(DateTime.parse(a['fechaEmision'] as String));
      } catch (_) {
        return 0;
      }
    });
    return lista;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    _usuarioId = prefs.getInt('id') ?? 0;
    _esSuperuser = prefs.getBool('is_superuser') == true;
    _operador =
        (prefs.getString('name') ?? prefs.getString('username') ?? 'OPERADOR')
            .toUpperCase();
    await _cargarEtiquetasUsuarios(prefs);
    _multasCache = await obtenerMultasGuardadas();
    if (_multasCache.isEmpty) {
      try {
        _multasCache = await fetchMultas();
      } catch (_) {}
    }
    await _cargar();
  }

  Future<void> _cargarEtiquetasUsuarios(SharedPreferences prefs) async {
    if (!_esSuperuser) return;

    void insertarUsuario(Map<String, dynamic> item) {
      final id = item['id'] as int? ?? 0;
      if (id <= 0) return;
      final username = (item['username'] as String? ?? '').trim();
      final first = (item['first_name'] as String? ?? '').trim();
      final last = (item['last_name'] as String? ?? '').trim();
      final full = '$first $last'.trim();
      final nombre = full.isNotEmpty ? full : username;
      if (nombre.isNotEmpty) _usuariosPorId[id] = nombre;
    }

    final rawCache = prefs.getString('cache_admin_usuarios');
    if (rawCache != null && rawCache.isNotEmpty) {
      try {
        final decoded = json.decode(rawCache);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) insertarUsuario(item);
          }
        }
      } catch (_) {}
    }

    if (_usuariosPorId.isNotEmpty) return;

    try {
      final token = (prefs.getString('token') ?? '').trim();
      final uri = token.isNotEmpty
          ? Uri.parse(
              'https://simert.transitoelguabo.gob.ec/api/gestion-usuarios/',
            ).replace(queryParameters: {'_tk': token})
          : Uri.parse(
              'https://simert.transitoelguabo.gob.ec/api/gestion-usuarios/',
            );

      final response = await HttpMonitorizado.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Token $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) insertarUsuario(item);
          }
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool forceRefresh = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final items = await _svc.getDetallesHoy(
        _usuarioId,
        _multasCache,
        forceRefresh: forceRefresh,
        verTodasUsuarios: _esSuperuser,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  // ─── Print / PDF ──────────────────────────────────────────────────────────
  Future<void> _accionReimprimir(Map<String, dynamic> item) async {
    final idDetalle = item['idDetalle'] as int;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _procesandoId = idDetalle);
    final operadorMulta = _resolverOperadorItem(item);

    String resultado;
    if (_gestorImpresora.estaConectada) {
      final ok = await _gestorImpresora.imprimirMultaSilenciosa(
        placa: item['placa'] as String,
        tipoMulta: item['tipoMulta'] as String,
        valor: (item['valor'] as num).toDouble(),
        fechaEmision: item['fechaEmision'] as String,
        ubicacion: item['ubicacion'] as String,
        numeroComprobante: item['comprobante'] as String,
        observacion: item['observacion'] as String,
        usuario: operadorMulta,
        idNotificacion: item['idNotificacion'] as int,
      );
      resultado = ok
          ? 'Ticket enviado a la impresora.'
          : 'No se pudo enviar a la impresora.';
    } else {
      // No hay impresora → ofrecer conectar primero o guardar como PDF
      final accion = await _mostrarDialogoSinImpresora();
      if (accion == _AccionSinImpresora.conectar) {
        if (!mounted) {
          setState(() => _procesandoId = null);
          return;
        }
        final conectado = await mostrarDialogoConectarImpresora(context);
        if (conectado == true && mounted) {
          setState(() {});
          if (_gestorImpresora.estaConectada) {
            final ok = await _gestorImpresora.imprimirMultaSilenciosa(
              placa: item['placa'] as String,
              tipoMulta: item['tipoMulta'] as String,
              valor: (item['valor'] as num).toDouble(),
              fechaEmision: item['fechaEmision'] as String,
              ubicacion: item['ubicacion'] as String,
              numeroComprobante: item['comprobante'] as String,
              observacion: item['observacion'] as String,
              usuario: operadorMulta,
              idNotificacion: item['idNotificacion'] as int,
            );
            resultado = ok
                ? 'Ticket enviado a la impresora.'
                : 'No se pudo enviar a la impresora.';
          } else {
            resultado = 'La impresora no se conectó.';
          }
        } else {
          setState(() => _procesandoId = null);
          return;
        }
      } else if (accion == _AccionSinImpresora.pdf) {
        final ruta = await _guardarComoPdf(item);
        resultado = ruta != null
            ? 'PDF guardado en:\n$ruta'
            : 'No se pudo guardar el PDF.';
      } else {
        setState(() => _procesandoId = null);
        return;
      }
    }

    if (mounted) {
      setState(() => _procesandoId = null);
      _mostrarResultadoConMessenger(messenger, resultado);
    }
  }

  Future<_AccionSinImpresora?> _mostrarDialogoSinImpresora() {
    return showDialog<_AccionSinImpresora>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sin impresora conectada'),
        content: const Text(
          'No hay ninguna impresora Bluetooth conectada.\n¿Qué deseas hacer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, _AccionSinImpresora.pdf),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Guardar PDF'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _colorPrimario),
            onPressed: () => Navigator.pop(ctx, _AccionSinImpresora.conectar),
            icon: const Icon(Icons.bluetooth, color: Colors.white),
            label: const Text(
              'Conectar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _guardarComoPdf(Map<String, dynamic> item) async {
    try {
      final doc = pw.Document();
      final operadorMulta = _resolverOperadorItem(item);
      final placa = item['placa'] as String;
      final tipoMulta = item['tipoMulta'] as String;
      final valor = (item['valor'] as num).toDouble();
      final fecha = item['fechaEmision'] as String;
      final fechaFormateada = _formatearFechaHora(fecha);
      final ubicacion = item['ubicacion'] as String;
      final comprobante = item['comprobante'] as String;
      final observacion = item['observacion'] as String;
      final idNotificacion = item['idNotificacion'] as int;
      final nombrePersona = (item['nombrePersona'] ?? '').toString().trim();
      final cedula = (item['cedula'] ?? '').toString().trim();
      final marca = (item['marca'] ?? '').toString().trim();
      final modelo = (item['modelo'] ?? '').toString().trim();
      final color = (item['color'] ?? '').toString().trim();
      final tipoVehiculo = (item['tipoVehiculo'] ?? '').toString().trim();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'SIMERT',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Sistema Municipal de Estacionamiento\nRegulado y Tarifado',
                      style: const pw.TextStyle(fontSize: 9),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'INFRACCIÓN DE TRÁNSITO',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _pdfFila('N° Comprobante:', comprobante),
              _pdfFila('N° Notificación:', idNotificacion.toString()),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _pdfFila('Placa:', placa),
              if (nombrePersona.isNotEmpty) _pdfFila('Persona:', nombrePersona),
              if (cedula.isNotEmpty) _pdfFila('Cédula:', cedula),
              if (marca.isNotEmpty) _pdfFila('Marca:', marca),
              if (modelo.isNotEmpty) _pdfFila('Modelo:', modelo),
              if (color.isNotEmpty) _pdfFila('Color:', color),
              if (tipoVehiculo.isNotEmpty)
                _pdfFila('Tipo vehículo:', tipoVehiculo),
              _pdfFila('Tipo de Infracción:', tipoMulta),
              _pdfFila('Valor:', '\$${valor.toStringAsFixed(2)}'),
              _pdfFila('Fecha / Hora:', fechaFormateada),
              _pdfFila('Ubicación:', ubicacion),
              if (observacion.isNotEmpty) _pdfFila('Observación:', observacion),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _pdfFila('Operador:', operadorMulta),
            ],
          ),
        ),
      );

      final bytes = await doc.save();
      final Directory dir;
      if (Platform.isAndroid) {
        final dl = Directory('/storage/emulated/0/Download');
        dir = await dl.exists() ? dl : await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final placaClean = placa.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final file = File('${dir.path}/multa_${idNotificacion}_$placaClean.pdf');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  pw.Widget _pdfFila(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );

  void _mostrarResultadoConMessenger(
    ScaffoldMessengerState messenger,
    String mensaje,
  ) {
    final esExito = mensaje.startsWith('Ticket') || mensaje.startsWith('PDF');
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              esExito ? Icons.check_circle : Icons.warning_amber,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: esExito ? Colors.green[700] : Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _resolverOperadorItem(Map<String, dynamic> item) {
    final emisor = (item['usuarioEmisor'] ?? '').toString().trim();
    if (emisor.isNotEmpty && emisor.toLowerCase() != 'null') return emisor;

    final usuarioId = int.tryParse((item['usuarioId'] ?? '').toString()) ?? 0;
    if (usuarioId > 0) {
      final nombre = _usuariosPorId[usuarioId]?.trim() ?? '';
      if (nombre.isNotEmpty) return nombre;
      return 'USUARIO #$usuarioId';
    }

    return _operador;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────
  String _formatearFechaHora(String fechaStr) {
    try {
      final dt = DateTime.parse(fechaStr).toLocal();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes  $hora:$min';
    } catch (_) {
      return fechaStr;
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
                gradient: AppColores.gradientePrincipal,
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
                    'Reimprimir Multa',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Permite reimprimir comprobantes de multas emitidas anteriormente. Seleccione la multa que desea reimprimir.',
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

  // ─── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: _buildAppBar(), body: _buildBody());
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: const Text(
        'Reimprimir multa',
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
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          tooltip: 'Información',
          onPressed: () => _mostrarInfo(context),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Forzar actualización desde servidor',
          onPressed: () => _cargar(forceRefresh: true),
        ),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: AppColores.gradientePrincipal,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          color: Colors.white.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.calendar_month, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Este mes - ${_itemsFiltrados.length} multa${_itemsFiltrados.length == 1 ? '' : 's'}${_textoBusqueda.isNotEmpty ? ' (filtrado)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              _buildScopeBadge(),
              const SizedBox(width: 8),
              _buildEstadoImpresora(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEstadoImpresora() {
    final conectada = _gestorImpresora.estaConectada;
    return GestureDetector(
      onTap: () async {
        final r = await mostrarDialogoConectarImpresora(context);
        if (r == true && mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: conectada
              ? Colors.green.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: conectada
                ? Colors.green.withValues(alpha: 0.6)
                : Colors.white30,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              conectada ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: conectada ? Colors.greenAccent : Colors.white60,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              conectada ? 'Impresora lista' : 'Sin impresora',
              style: TextStyle(
                color: conectada ? Colors.greenAccent : Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeBadge() {
    final esAdmin = _esSuperuser;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: esAdmin
            ? AppColores.acentoAdmin.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esAdmin
              ? AppColores.acentoAdmin.withValues(alpha: 0.55)
              : Colors.white30,
        ),
      ),
      child: Text(
        esAdmin ? 'Vista global (ADMIN)' : 'Mis multas',
        style: TextStyle(
          color: esAdmin ? AppColores.acentoAdmin : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_cargando) return _buildCargando();
    if (_error != null) return _buildError();
    return Column(
      children: [
        _buildBarraBusqueda(),
        Expanded(
          child: _itemsFiltrados.isEmpty
              ? _buildVacio()
              : RefreshIndicator(
                  onRefresh: () => _cargar(forceRefresh: true),
                  color: _colorPrimario,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: _itemsFiltrados.length,
                    itemBuilder: (_, i) => _buildCard(_itemsFiltrados[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBarraBusqueda() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoBusquedaApp(
            controller: _busquedaCtrl,
            hintText: 'Buscar por placa, tipo...',
            filledColor: _colorFondo,
            onChanged: (v) => setState(() => _textoBusqueda = v.trim()),
            onSearch: () {
              FocusScope.of(context).unfocus();
              setState(() => _textoBusqueda = _busquedaCtrl.text.trim());
            },
            onClear: () => setState(() => _textoBusqueda = ''),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _legendItem(
                  'Grave/Prohibida',
                  _colorPorTipoInfraccion('prohibido grave'),
                ),
                const SizedBox(width: 8),
                _legendItem(
                  'Ausencia/Sin tarjeta',
                  _colorPorTipoInfraccion('ausencia de tarjeta'),
                ),
                const SizedBox(width: 8),
                _legendItem(
                  'Tiempo/Exceso',
                  _colorPorTipoInfraccion('exceso de tiempo'),
                ),
                const SizedBox(width: 8),
                _legendItem(
                  'Otros tipos',
                  _colorPorTipoInfraccion('otros tipos'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCargando() {
    return const EstadoCargaApp(
      icono: Icons.receipt_long_rounded,
      mensaje: 'Cargando multas de hoy...',
      colorInicio: _colorPrimario,
      colorFin: Colors.black,
      colorProgreso: Color(0xFF1565C0),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No se pudo cargar la información',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: _colorPrimario),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _colorPrimario.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: _colorPrimario,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sin multas registradas hoy',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _colorTexto,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Las multas que registres aparecerán aquí para reimprimir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh, color: _colorPrimario),
              label: const Text(
                'Actualizar',
                style: TextStyle(color: _colorPrimario),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _colorPrimario),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final idDetalle = item['idDetalle'] as int;
    final procesando = _procesandoId == idDetalle;
    final placa = item['placa'] as String;
    final tipoMulta = item['tipoMulta'] as String;
    final valor = (item['valor'] as num).toDouble();
    final fechaHora = _formatearFechaHora(item['fechaEmision'] as String);
    final comprobante = item['comprobante'] as String;
    final ubicacion = item['ubicacion'] as String;
    final nombrePersona = (item['nombrePersona'] ?? '').toString().trim();
    final cedula = (item['cedula'] ?? '').toString().trim();
    final marca = (item['marca'] ?? '').toString().trim();
    final modelo = (item['modelo'] ?? '').toString().trim();
    final color = (item['color'] ?? '').toString().trim();
    final tipoVehiculo = (item['tipoVehiculo'] ?? '').toString().trim();
    final usuarioNotifico = _resolverOperadorItem(item);
    final conectada = _gestorImpresora.estaConectada;
    final colorAcento = _colorPorTipoInfraccion(tipoMulta);
    final iconoVehiculo = _iconoPorFormatoPlaca(placa);
    final vehiculoTexto = [
      marca,
      modelo,
      color,
    ].where((e) => e.isNotEmpty).join(' · ');

    return TarjetaListaApp(
      colorAcento: colorAcento,
      onTap: procesando ? null : () => _accionReimprimir(item),
      avatar: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: procesando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(iconoVehiculo, color: Colors.white, size: 20),
        ),
      ),
      titulo: placa,
      subtitulo: tipoMulta,
      encabezadoDerecha: Icon(
        conectada ? Icons.print_rounded : Icons.picture_as_pdf_rounded,
        color: Colors.white,
        size: 20,
      ),
      cuerpo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fechaHora,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorAcento.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorAcento.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '\$${valor.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colorAcento,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              if (comprobante.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'N° $comprobante',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (ubicacion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              ubicacion,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (nombrePersona.isNotEmpty || cedula.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 13,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    nombrePersona.isNotEmpty
                        ? (cedula.isNotEmpty
                              ? '$nombrePersona · CI $cedula'
                              : nombrePersona)
                        : 'CI $cedula',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (usuarioNotifico.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 13,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Notificó: $usuarioNotifico',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (vehiculoTexto.isNotEmpty || tipoVehiculo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.directions_car_outlined,
                  size: 13,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    vehiculoTexto.isNotEmpty
                        ? (tipoVehiculo.isNotEmpty
                              ? '$vehiculoTexto · $tipoVehiculo'
                              : vehiculoTexto)
                        : tipoVehiculo,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _colorPorTipoInfraccion(String tipoMulta) {
    final t = tipoMulta.toLowerCase();

    if (t.contains('prohibid') ||
        t.contains('discapac') ||
        t.contains('peatonal') ||
        t.contains('grave') ||
        t.contains('peligro')) {
      return AppColores.error;
    }

    if (t.contains('ausencia') ||
        t.contains('sin tarjeta') ||
        t.contains('caducad') ||
        t.contains('vencid')) {
      return const Color(0xFFAD7A00);
    }

    if (t.contains('fuera') || t.contains('tiempo') || t.contains('exceso')) {
      return AppColores.info;
    }

    return const Color(0xFF1565C0);
  }

  IconData _iconoPorFormatoPlaca(String placa) {
    final p = placa.trim().toUpperCase();
    if (RegExp(r'^[A-Z]{2}\d{3}[A-Z]$').hasMatch(p)) {
      return Icons.two_wheeler_rounded;
    }
    if (RegExp(r'^[A-Z]{3}\d{4}$').hasMatch(p)) {
      return Icons.directions_car_filled_rounded;
    }
    return Icons.directions_car_outlined;
  }
}

enum _AccionSinImpresora { conectar, pdf }

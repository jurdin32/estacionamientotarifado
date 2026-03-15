import 'dart:io';

import 'package:estacionamientotarifado/servicios/gestorImpresora.dart';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart';
import 'package:estacionamientotarifado/servicios/servicioTiposMultas.dart';
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
  static const Color _colorPrimario = Color(0xFF001F54);
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
            (item['comprobante'] as String).toLowerCase().contains(q);
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
    _operador =
        (prefs.getString('name') ?? prefs.getString('username') ?? 'OPERADOR')
            .toUpperCase();
    _multasCache = await obtenerMultasGuardadas();
    if (_multasCache.isEmpty) {
      try {
        _multasCache = await fetchMultas();
      } catch (_) {}
    }
    await _cargar();
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
        usuario: _operador,
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
              usuario: _operador,
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
      final placa = item['placa'] as String;
      final tipoMulta = item['tipoMulta'] as String;
      final valor = (item['valor'] as num).toDouble();
      final fecha = item['fechaEmision'] as String;
      final ubicacion = item['ubicacion'] as String;
      final comprobante = item['comprobante'] as String;
      final observacion = item['observacion'] as String;
      final idNotificacion = item['idNotificacion'] as int;

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
              _pdfFila('Tipo de Infracción:', tipoMulta),
              _pdfFila('Valor:', '\$${valor.toStringAsFixed(2)}'),
              _pdfFila('Fecha / Hora:', fecha),
              _pdfFila('Ubicación:', ubicacion),
              if (observacion.isNotEmpty) _pdfFila('Observación:', observacion),
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _pdfFila('Operador:', _operador),
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

  // ─── Helpers ─────────────────────────────────────────────────────────────
  String _formatearFechaHora(String fechaStr) {
    try {
      final dt = DateTime.parse(fechaStr);
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes  $hora:$min';
    } catch (_) {
      return fechaStr;
    }
  }

  // ─── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
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
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Forzar actualización desde servidor',
          onPressed: () => _cargar(forceRefresh: true),
        ),
      ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Colors.white.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.calendar_month, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                'Este mes - ${_itemsFiltrados.length} multa${_itemsFiltrados.length == 1 ? '' : 's'}${_textoBusqueda.isNotEmpty ? ' (filtrado)' : ''}',

                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: _busquedaCtrl,
        onChanged: (v) => setState(() => _textoBusqueda = v.trim()),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar por placa, tipo...',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: _colorPrimario, size: 20),
          suffixIcon: _textoBusqueda.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _busquedaCtrl.clear();
                    setState(() => _textoBusqueda = '');
                  },
                )
              : null,
          filled: true,
          fillColor: _colorFondo,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, Color(0xFF5E17EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
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
            'Cargando multas de hoy...',
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
    final conectada = _gestorImpresora.estaConectada;
    final inicial = placa.isNotEmpty ? placa[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 2,
      shadowColor: _colorPrimario.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _colorPrimario.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: procesando ? null : () => _accionReimprimir(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _colorPrimario.withValues(alpha: 0.10),
                child: procesando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _colorPrimario,
                        ),
                      )
                    : Text(
                        inicial,
                        style: const TextStyle(
                          color: _colorPrimario,
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
                      placa,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _colorPrimario,
                      ),
                    ),
                    Text(
                      tipoMulta,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      fechaHora,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _colorPrimario.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _colorPrimario.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '\$${valor.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: _colorPrimario,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (comprobante.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            'N° $comprobante',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (ubicacion.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ubicacion,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    conectada
                        ? Icons.print_rounded
                        : Icons.picture_as_pdf_rounded,
                    color: procesando ? Colors.grey : _colorPrimario,
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AccionSinImpresora { conectar, pdf }

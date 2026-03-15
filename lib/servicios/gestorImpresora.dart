import 'package:flutter/material.dart';
import '../../servicios/servicioImpresionTermica.dart';
import 'package:estacionamientotarifado/tarjetas/views/WidgetsImpresora.dart';

/// Clase auxiliar para manejar impresiones de forma sencilla
class GestorImpresora {
  static final GestorImpresora _instancia = GestorImpresora._internal();

  factory GestorImpresora() => _instancia;
  GestorImpresora._internal() {
    // Intentar cargar configuración guardada y conectar en background
    Future.microtask(() async {
      try {
        await _servicio.cargarConfiguracionYConectarSiAplica();
      } catch (e) {
        // No bloquear inicialización si falla
        print('⚠️ Error al cargar configuración de impresora en inicio: $e');
      }
    });
  }

  final ServicioImpresionTermica _servicio = ServicioImpresionTermica();

  /// Imprime una multa y muestra mensajes al usuario
  Future<bool> imprimirMultaConDialogo({
    required BuildContext context,
    required String placa,
    required String tipoMulta,
    required double valor,
    required String fechaEmision,
    required String ubicacion,
    required String numeroComprobante,
    required String observacion,
    required String usuario,
    required int idNotificacion,
  }) async {
    // Verificar conexión
    if (!_servicio.estaConectado) {
      _mostrarDialogoError(
        context,
        'Sin conexión',
        'No hay impresora conectada. Por favor, conecte una impresora Bluetooth.',
      );
      return false;
    }

    // Mostrar diálogo de confirmación
    bool? confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Confirmar impresión'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilaDatos('Placa:', placa),
            _buildFilaDatos('Tipo:', tipoMulta),
            _buildFilaDatos('Valor:', '\$${valor.toStringAsFixed(2)}'),
            _buildFilaDatos('Ubicación:', ubicacion),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Imprimir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return false;

    // Mostrar indicador de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Imprimiendo...'),
          ],
        ),
      ),
    );

    try {
      await _servicio.imprimirMulta(
        placa: placa,
        tipoMulta: tipoMulta,
        valor: valor,
        fechaEmision: fechaEmision,
        ubicacion: ubicacion,
        numeroComprobante: numeroComprobante,
        observacion: observacion,
        usuario: usuario,
        idNotificacion: idNotificacion,
      );

      Navigator.pop(context); // Cerrar diálogo de progreso

      _mostrarDialogoExito(
        context,
        'Éxito',
        'El ticket ha sido impreso correctamente.',
      );

      return true;
    } catch (e) {
      Navigator.pop(context); // Cerrar diálogo de progreso

      _mostrarDialogoError(
        context,
        'Error de impresión',
        'No se pudo imprimir el ticket: $e',
      );

      return false;
    }
  }

  /// Muestra el diálogo de configuración de la impresora
  void mostrarConfiguracionImpresora(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ConfiguracionImpresoraPage(servicio: _servicio),
      ),
    );
  }

  /// Verifica si hay impresora conectada
  bool get estaConectada => _servicio.estaConectado;

  /// Imprime sin mostrar diálogos de confirmación (ideal para impresión automática)
  Future<bool> imprimirMultaSilenciosa({
    BuildContext? context,
    required String placa,
    required String tipoMulta,
    required double valor,
    required String fechaEmision,
    required String ubicacion,
    required String numeroComprobante,
    required String observacion,
    required String usuario,
    required int idNotificacion,
  }) async {
    try {
      // Si no está conectado, intentar reconectar con la configuración guardada
      if (!_servicio.estaConectado) {
        await _servicio.cargarConfiguracionYConectarSiAplica();
      }

      if (!_servicio.estaConectado) {
        if (context != null) {
          _mostrarDialogoError(
            context,
            'Sin impresora',
            'No hay impresora conectada. Verifique la configuración.',
          );
        }
        return false;
      }

      await _servicio.imprimirMulta(
        placa: placa,
        tipoMulta: tipoMulta,
        valor: valor,
        fechaEmision: fechaEmision,
        ubicacion: ubicacion.toUpperCase(),
        numeroComprobante: numeroComprobante,
        observacion: observacion.toUpperCase(),
        usuario: usuario,
        idNotificacion: idNotificacion,
      );

      if (context != null) {
        _mostrarDialogoExito(
          context,
          'Impresión enviada',
          'El ticket fue enviado a la impresora.',
        );
      }
      return true;
    } catch (e) {
      if (context != null) {
        _mostrarDialogoError(
          context,
          'Error de impresión',
          'No se pudo imprimir el ticket: $e',
        );
      }
      return false;
    }
  }

  /// Obtiene el estado actual de la impresora
  Future<Map<String, dynamic>> obtenerEstado() async {
    return await _servicio.verificarEstado();
  }

  // ==================== MÉTODOS PRIVADOS ====================

  void _mostrarDialogoError(
    BuildContext context,
    String titulo,
    String mensaje,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoExito(
    BuildContext context,
    String titulo,
    String mensaje,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilaDatos(String etiqueta, String valor) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}

// ==================== PÁGINA DE CONFIGURACIÓN ====================

class _ConfiguracionImpresoraPage extends StatefulWidget {
  final ServicioImpresionTermica servicio;

  const _ConfiguracionImpresoraPage({required this.servicio});

  @override
  State<_ConfiguracionImpresoraPage> createState() =>
      _ConfiguracionImpresoraPageState();
}

class _ConfiguracionImpresoraPageState
    extends State<_ConfiguracionImpresoraPage> {
  bool _cargando = false;
  Map<String, dynamic> _estado = {};

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    setState(() => _cargando = true);
    _estado = await widget.servicio.verificarEstado();
    // Cargar configuración persistente (si existe)
    try {
      final cfg = await widget.servicio.obtenerConfiguracionGuardada();
      setState(() {
        _configGuardada = cfg;
      });
    } catch (e) {
      _configGuardada = {};
    }
    setState(() => _cargando = false);
  }

  Map<String, String?> _configGuardada = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configuración - Impresora Bluetooth'),
        backgroundColor: Colors.blue[800],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCardEstado(),
                  SizedBox(height: 24),
                  _buildInformacionDispositivos(),
                  SizedBox(height: 24),
                  _buildInstrucciones(),
                ],
              ),
            ),
    );
  }

  Widget _buildCardEstado() {
    bool bluetoothActivo = _estado['bluetoothActivo'] ?? false;
    bool conectado = _estado['conectado'] ?? false;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.bluetooth,
                color: bluetoothActivo ? Colors.blue : Colors.red,
              ),
              title: Text('Bluetooth'),
              subtitle: Text(bluetoothActivo ? 'Activado' : 'Desactivado'),
            ),
            Divider(),
            ListTile(
              leading: Icon(
                Icons.link,
                color: conectado ? Colors.green : Colors.grey,
              ),
              title: Text('Impresora'),
              subtitle: Text(conectado ? 'Conectada' : 'No conectada'),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.devices),
              title: Text('Dispositivos emparejados'),
              subtitle: Text('${_estado['dispositivosEmparejados'] ?? 0}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformacionDispositivos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSeccionImpresoraPorDefecto(),
        SizedBox(height: 12),
        Text(
          'Información del Dispositivo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_estado['dispositivoConectado'] != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dirección MAC:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(_estado['dispositivoConectado'] ?? 'N/A'),
                      SizedBox(height: 12),
                    ],
                  ),
                if (_estado['error'] != null)
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Error: ${_estado['error']}',
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionImpresoraPorDefecto() {
    final tipo = _configGuardada['printer_type'];
    final address = _configGuardada['printer_address'];
    final port = _configGuardada['printer_port'];

    String descripcion;
    if (tipo == null) {
      descripcion = 'No hay impresora por defecto configurada.';
    } else if (tipo == 'bluetooth') {
      descripcion = 'Bluetooth — ${address ?? 'desconocida'}';
    } else if (tipo == 'usb') {
      descripcion = 'USB/COM — ${port ?? 'desconocido'}';
    } else {
      descripcion = 'Tipo desconocido';
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Impresora por defecto',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(descripcion),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    // Abrir diálogo de conexión (permite seleccionar y conectar)
                    final res = await mostrarDialogoConectarImpresora(context);
                    if (res == true) {
                      await _cargarEstado();
                    }
                  },
                  icon: Icon(Icons.swap_horiz),
                  label: Text('Seleccionar impresora por defecto'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    // Borrar configuración guardada
                    await widget.servicio.limpiarConfiguracion();
                    await _cargarEstado();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Configuración de impresora borrada'),
                      ),
                    );
                  },
                  icon: Icon(Icons.delete_outline),
                  label: Text('Borrar configuración'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstrucciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guía de Configuración',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPasoInstruccion(
                  numero: 1,
                  titulo: 'Emparejar dispositivo',
                  descripcion:
                      'Ve a Configuración > Bluetooth de tu dispositivo\n'
                      'Busca tu impresora Bluetooth y emparéjala',
                ),
                SizedBox(height: 12),
                _buildPasoInstruccion(
                  numero: 2,
                  titulo: 'Verificar Bluetooth',
                  descripcion:
                      'Asegúrate de que Bluetooth esté activado\n'
                      'en tu dispositivo Android',
                ),
                SizedBox(height: 12),
                _buildPasoInstruccion(
                  numero: 3,
                  titulo: 'Conectar desde la app',
                  descripcion:
                      'Abre esta pantalla y selecciona tu\n'
                      'impresora de la lista de dispositivos',
                ),
                SizedBox(height: 12),
                _buildPasoInstruccion(
                  numero: 4,
                  titulo: 'Imprimir',
                  descripcion:
                      'Una vez conectada, podrás imprimir\n'
                      'tus tickets de forma inalámbrica',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasoInstruccion({
    required int numero,
    required String titulo,
    required String descripcion,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.blue[700],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$numero',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                descripcion,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

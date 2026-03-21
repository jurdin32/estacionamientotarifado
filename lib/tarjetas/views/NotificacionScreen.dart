// pantallas/notificaciones_screen.dart
import 'dart:io';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:estacionamientotarifado/tarjetas/models/Multa.dart';
import 'package:estacionamientotarifado/servicios/servicioTiposMultas.dart';
import 'package:estacionamientotarifado/servicios/gestorImpresora.dart';
import 'package:estacionamientotarifado/servicios/servicioNotificaciones2.dart'
    as svc2;
import 'package:estacionamientotarifado/tarjetas/views/ReimpresionScreen.dart';
import 'package:estacionamientotarifado/tarjetas/views/WidgetsImpresora.dart';
import '../../snnipers/cambia_mayusculas.dart';

class Notificacionesscreen extends StatefulWidget {
  const Notificacionesscreen({super.key});

  /// Llama esto desde HomeScreen para pre-cargar los tipos de multas en caché.
  static Future<void> preWarmCache() async {
    final guardadas = await obtenerMultasGuardadas();
    if (guardadas.isNotEmpty) return; // ya hay caché
    try {
      final desdeApi = await fetchMultas();
      if (desdeApi.isNotEmpty) await guardarMultasEnPreferencias(desdeApi);
    } catch (_) {
      // Silencioso — se cargará al entrar a la pantalla
    }
  }

  @override
  State<Notificacionesscreen> createState() => _NotificacionesscreenState();
}

class _NotificacionesscreenState extends State<Notificacionesscreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final GestorImpresora _gestorImpresora = GestorImpresora();

  final TextEditingController _fechaEmisionController = TextEditingController();
  final TextEditingController _ubicacionController = TextEditingController();
  final TextEditingController _placaController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();
  final TextEditingController _observacionController = TextEditingController();
  final TextEditingController _numeroComprobanteController =
      TextEditingController();

  // Focus nodes para controlar el teclado
  final FocusNode _placaFocusNode = FocusNode();
  final FocusNode _ubicacionFocusNode = FocusNode();
  final FocusNode _observacionFocusNode = FocusNode();

  List<Multa> multas = [];
  Multa? multaSeleccionada;
  bool cargando = true;

  // Variables para controlar el scroll cuando el teclado aparece
  final ScrollController _scrollController = ScrollController();

  // Variables para control visual en tiempo real
  bool _placaValida = false;
  String _mensajeError = '';

  // Variables para gestión de imágenes
  final List<File> _imagenesSeleccionadas = [];
  static const int _maxImagenes = 3;
  bool _subiendoEvidencias = false;

  // Colores coherentes con el diseño de la app
  final Color _colorPrimario = const Color(0xFF0A1628);
  final Color _colorPurple = const Color(0xFF1565C0);
  final Color _colorAcento = const Color(0xFFFF9800);
  final Color _colorFondo = const Color(0xFFF0F4FF);
  final Color _colorTexto = const Color(0xFF333333);
  final Color _colorBorde = const Color(0xFFE0E0E0);
  final Color _colorError = const Color(0xFFD32F2F);
  final Color _colorInfo = const Color(0xFF1976D2);

  // Variables de usuario
  String username = '';
  String name = '';
  String email = '';
  int usuario_id = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _cargarMultas();

    _placaController.addListener(() {
      _validarPlacaEnTiempoReal();
      _actualizarEstadoBoton();
    });

    _ubicacionController.addListener(_actualizarEstadoBoton);
    _observacionController.addListener(_actualizarEstadoBoton);
    _numeroComprobanteController.addListener(_actualizarEstadoBoton);
    _fechaEmisionController.addListener(_actualizarEstadoBoton);

    _establecerFechaHoraActual();
    _agregarFocusListeners();
  }

  void _actualizarEstadoBoton() {
    if (mounted) {
      setState(() {});
    }
  }

  void _agregarFocusListeners() {
    _placaFocusNode.addListener(() {
      if (_placaFocusNode.hasFocus) {
        _scrollToField(0.0);
      }
    });

    _ubicacionFocusNode.addListener(() {
      if (_ubicacionFocusNode.hasFocus) {
        _scrollToField(100.0);
      }
    });

    _observacionFocusNode.addListener(() {
      if (_observacionFocusNode.hasFocus) {
        _scrollToField(200.0);
      }
    });
  }

  void _scrollToField(double offset) {
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await NotificacionService.loadUserData();
      setState(() {
        username = userData['username'] ?? '';
        name = userData['name'] ?? '';
        email = userData['email'] ?? '';
        usuario_id = userData['id'] ?? 0;
      });
    } catch (e) {
      setState(() {
        usuario_id = 0;
      });
    }
  }

  void _establecerFechaHoraActual() {
    final now = DateTime.now();
    _fechaEmisionController.text = NotificacionService.formatearFechaHora(now);
  }

  // MÉTODOS PARA GESTIÓN DE IMÁGENES
  Future<void> _seleccionarImagenes() async {
    try {
      final imagenes = await NotificacionService.seleccionarImagenes(
        _picker,
        _maxImagenes,
      );

      if (imagenes.isNotEmpty) {
        setState(() {
          // Mantener máximo 3 imágenes
          final totalDisponible = _maxImagenes - _imagenesSeleccionadas.length;
          if (totalDisponible > 0) {
            final imagenesAAgregar = imagenes.length > totalDisponible
                ? imagenes.sublist(0, totalDisponible)
                : imagenes;
            _imagenesSeleccionadas.addAll(imagenesAAgregar);
          }
        });
        _actualizarEstadoBoton();

        if (imagenes.length > (_maxImagenes - _imagenesSeleccionadas.length)) {
          _mostrarSnackBar(
            'Solo se pueden seleccionar hasta $_maxImagenes imágenes',
          );
        }
      }
    } catch (e) {
      _mostrarSnackBar('Error al seleccionar imágenes: $e');
    }
  }

  Future<void> _tomarFoto() async {
    try {
      if (_imagenesSeleccionadas.length >= _maxImagenes) {
        _mostrarSnackBar(
          'Ya has seleccionado el máximo de $_maxImagenes imágenes',
        );
        return;
      }

      final foto = await NotificacionService.tomarFoto(_picker);

      if (foto != null) {
        setState(() {
          _imagenesSeleccionadas.add(foto);
        });
        _actualizarEstadoBoton();
        _mostrarSnackBar('Foto tomada exitosamente');
      }
    } catch (e) {
      _mostrarSnackBar('Error al tomar foto: $e');
    }
  }

  void _eliminarImagen(int index) {
    setState(() {
      _imagenesSeleccionadas.removeAt(index);
    });
    _actualizarEstadoBoton();
    _mostrarSnackBar('Imagen eliminada');
  }

  void _mostrarSnackBar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _seleccionarFechaHora() async {
    final DateTime? fechaSeleccionada = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _colorPrimario,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _colorTexto,
            ),
            dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (fechaSeleccionada != null) {
      final TimeOfDay? horaSeleccionada = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(DateTime.now()),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: _colorPrimario,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: _colorTexto,
              ),
              dialogTheme: DialogThemeData(backgroundColor: Colors.white),
            ),
            child: child!,
          );
        },
      );

      if (horaSeleccionada != null) {
        final DateTime fechaHoraCompleta = DateTime(
          fechaSeleccionada.year,
          fechaSeleccionada.month,
          fechaSeleccionada.day,
          horaSeleccionada.hour,
          horaSeleccionada.minute,
        );

        setState(() {
          _fechaEmisionController.text = NotificacionService.formatearFechaHora(
            fechaHoraCompleta,
          );
        });
        _actualizarEstadoBoton();
      }
    }
  }

  void _validarPlacaEnTiempoReal() {
    final resultado = NotificacionService.validarPlacaEnTiempoReal(
      _placaController.text,
    );

    if (_placaController.text != resultado['textoConvertido']) {
      _placaController.value = _placaController.value.copyWith(
        text: resultado['textoConvertido'],
        selection: TextSelection.collapsed(
          offset: resultado['textoConvertido'].length,
        ),
      );
      return;
    }

    setState(() {
      _placaValida = resultado['valida'];
      _mensajeError = resultado['mensajeError'];
    });
  }

  Future<void> _cargarMultas() async {
    setState(() => cargando = true);

    // Cargar caché para mostrar rápido
    List<Multa> guardadas = await obtenerMultasGuardadas();
    if (guardadas.isNotEmpty) {
      setState(() {
        multas = guardadas;
        multaSeleccionada = multas.first;
        _totalController.text = multaSeleccionada!.valor.toStringAsFixed(2);
        cargando = false;
      });
      _actualizarEstadoBoton();
    }

    // Siempre recargar desde API para tener IDs actualizados
    try {
      List<Multa> desdeApi = await fetchMultas();
      if (desdeApi.isNotEmpty) {
        await guardarMultasEnPreferencias(desdeApi);
        setState(() {
          multas = desdeApi;
          multaSeleccionada = multas.first;
          _totalController.text = multaSeleccionada!.valor.toStringAsFixed(2);
          cargando = false;
        });
        _actualizarEstadoBoton();
      } else if (guardadas.isEmpty) {
        setState(() => cargando = false);
        _actualizarEstadoBoton();
      }
    } catch (e) {
      // Si el API falla y no hay caché, dejar vacío
      if (guardadas.isEmpty) {
        setState(() => cargando = false);
        _actualizarEstadoBoton();
      }
    }
  }

  void _guardarMulta() async {
    // Validar que se hayan seleccionado exactamente 3 fotos
    if (_imagenesSeleccionadas.length != 3) {
      _mostrarModalError(
        "Debe seleccionar exactamente 3 evidencias fotográficas. Actualmente tiene ${_imagenesSeleccionadas.length}.",
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (usuario_id == 0) {
        _mostrarModalError(
          "No se pudo identificar al usuario. Por favor, cierre la aplicación y vuelva a iniciar sesión.",
        );
        return;
      }

      // Validar que la fecha no sea futura
      final fechaIngresada = NotificacionService.parsearFechaHora(
        _fechaEmisionController.text,
      );
      final ahora = DateTime.now();

      if (fechaIngresada.isAfter(ahora)) {
        _mostrarModalError(
          "La fecha no puede ser futura. Por favor, seleccione una fecha y hora válida.",
        );
        return;
      }

      // Mostrar diálogo de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_colorPrimario),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Guardando multa...",
                    style: TextStyle(
                      fontSize: 16,
                      color: _colorTexto,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      try {
        // Crear la notificación usando el servicio
        final notificacion = NotificacionService.crearNotificacion(
          fechaEmision: _fechaEmisionController.text,
          ubicacion: _ubicacionController.text,
          placa: _placaController.text,
          observacion: _observacionController.text,
          numeroComprobante: _numeroComprobanteController.text,
          usuarioId: usuario_id,
        );

        // Crear el detalle usando el servicio
        final detalle = NotificacionService.crearDetalleNotificacion(
          notificacion: notificacion,
          multaSeleccionada: multaSeleccionada,
        );

        // Registrar la notificación
        final Map<String, dynamic> resultado =
            await NotificacionService.registrarNotificacion(detalle);

        // CERRAR EL DIÁLOGO DE CARGA PRIMERO
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        if (resultado['exito'] == true) {
          final int? idNotificacion = resultado['idNotificacion'];

          // Subir evidencias (siempre hay 3 fotos ahora)
          await _subirEvidencias(idNotificacion!);
        } else {
          String mensajeError = resultado['mensaje'] ?? 'Error desconocido';
          int statusCode = resultado['statusCode'] ?? 0;
          _mostrarModalError(
            "Error del servidor (Código $statusCode):\n$mensajeError",
          );
        }
      } catch (e) {
        // CERRAR EL DIÁLOGO DE CARGA EN CASO DE ERROR
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _mostrarModalError(
          "Error inesperado: $e\n\nPor favor, intente nuevamente.",
        );
      }
    }
  }

  Future<void> _subirEvidencias(int idNotificacion) async {
    setState(() => _subiendoEvidencias = true);

    // Mostrar diálogo de carga para evidencias
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_colorPrimario),
                ),
                const SizedBox(height: 16),
                Text(
                  "Subiendo evidencias...",
                  style: TextStyle(
                    fontSize: 16,
                    color: _colorTexto,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final resultado = await NotificacionService.subirEvidencias(
        idNotificacion,
        _imagenesSeleccionadas,
      );

      // CERRAR EL DIÁLOGO DE CARGA DE EVIDENCIAS
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      setState(() => _subiendoEvidencias = false);

      // Guardar en caché local para reimpresión rápida
      await svc2.CacheDetallesService.agregarItem({
        'idDetalle': 0,
        'idNotificacion': idNotificacion,
        'placa': _placaController.text.toUpperCase(),
        'tipoMulta': multaSeleccionada?.detalleMulta ?? '',
        'valor': multaSeleccionada?.valor ?? 0.0,
        'fechaEmision': _fechaEmisionController.text,
        'ubicacion': _ubicacionController.text,
        'comprobante': _numeroComprobanteController.text,
        'observacion': _observacionController.text,
        'anulado': false,
      });

      // Imprimir por Bluetooth o guardar PDF según disponibilidad
      final resultadoAccion = await _procesarImpresionOPdf(idNotificacion);

      _mostrarModalExito(
        idNotificacion: idNotificacion,
        evidenciasSubidas: resultado['totalExitosas'] ?? 0,
        totalEvidencias: resultado['totalEnviadas'] ?? 0,
        mensajeEvidencias: resultado['mensaje'],
        resultadoAccion: resultadoAccion,
      );
    } catch (e) {
      // CERRAR EL DIÁLOGO DE CARGA DE EVIDENCIAS EN CASO DE ERROR
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      setState(() => _subiendoEvidencias = false);

      // Guardar en caché local aunque las evidencias fallaron (la multa ya existe)
      await svc2.CacheDetallesService.agregarItem({
        'idDetalle': 0,
        'idNotificacion': idNotificacion,
        'placa': _placaController.text.toUpperCase(),
        'tipoMulta': multaSeleccionada?.detalleMulta ?? '',
        'valor': multaSeleccionada?.valor ?? 0.0,
        'fechaEmision': _fechaEmisionController.text,
        'ubicacion': _ubicacionController.text,
        'comprobante': _numeroComprobanteController.text,
        'observacion': _observacionController.text,
        'anulado': false,
      });

      // Imprimir por Bluetooth o guardar PDF aunque las evidencias fallaron
      final resultadoAccion = await _procesarImpresionOPdf(idNotificacion);

      _mostrarModalExito(
        idNotificacion: idNotificacion,
        evidenciasSubidas: 0,
        totalEvidencias: _imagenesSeleccionadas.length,
        mensajeEvidencias: 'Error subiendo evidencias: $e',
        resultadoAccion: resultadoAccion,
      );
    }
  }

  void _mostrarModalExito({
    int? idNotificacion,
    int evidenciasSubidas = 0,
    int totalEvidencias = 0,
    String? mensajeEvidencias,
    String? resultadoAccion,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.90,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Encabezado fijo
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_colorPrimario, _colorPurple],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "¡Multa Registrada!",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "La multa se ha registrado correctamente",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),

                // Contenido scrollable
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _colorFondo,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _colorBorde, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Resumen de la Multa",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _colorPrimario,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Información compacta
                              _buildInfoRowCompact(
                                "Placa:",
                                _placaController.text,
                              ),
                              const SizedBox(height: 6),
                              _buildInfoRowCompact(
                                "Tipo:",
                                multaSeleccionada?.detalleMulta ?? "",
                              ),
                              const SizedBox(height: 6),
                              _buildInfoRowCompact(
                                "Valor:",
                                "\$${multaSeleccionada?.valor.toStringAsFixed(2) ?? "0.00"}",
                              ),
                              const SizedBox(height: 6),
                              _buildInfoRowCompact(
                                "Fecha:",
                                _fechaEmisionController.text,
                              ),
                              const SizedBox(height: 6),
                              _buildInfoRowCompact(
                                "Ubicación:",
                                _ubicacionController.text,
                              ),
                              if (idNotificacion != null) ...[
                                const SizedBox(height: 6),
                                _buildInfoRowCompact(
                                  "ID Notificación:",
                                  idNotificacion.toString(),
                                ),
                              ],
                              const SizedBox(height: 6),
                              _buildInfoRowCompact(
                                "Evidencias:",
                                "$evidenciasSubidas/$totalEvidencias subidas",
                              ),
                              const SizedBox(height: 6),
                              _buildInfoRowCompact(
                                "Registrado por:",
                                name.isNotEmpty ? name : username,
                              ),
                            ],
                          ),
                        ),

                        if (mensajeEvidencias != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _colorInfo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _colorInfo, width: 1),
                            ),
                            child: Text(
                              mensajeEvidencias,
                              style: TextStyle(color: _colorInfo, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        if (resultadoAccion != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: resultadoAccion.startsWith('Ticket')
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : resultadoAccion.startsWith('PDF')
                                  ? Colors.blue.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: resultadoAccion.startsWith('Ticket')
                                    ? Colors.green
                                    : resultadoAccion.startsWith('PDF')
                                    ? Colors.blue
                                    : Colors.orange,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  resultadoAccion.startsWith('Ticket')
                                      ? Icons.print
                                      : resultadoAccion.startsWith('PDF')
                                      ? Icons.picture_as_pdf
                                      : Icons.warning_amber,
                                  size: 18,
                                  color: resultadoAccion.startsWith('Ticket')
                                      ? Colors.green[700]
                                      : resultadoAccion.startsWith('PDF')
                                      ? Colors.blue[700]
                                      : Colors.orange[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    resultadoAccion,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          resultadoAccion.startsWith('Ticket')
                                          ? Colors.green[800]
                                          : resultadoAccion.startsWith('PDF')
                                          ? Colors.blue[800]
                                          : Colors.orange[800],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Botón en la parte inferior - FUERA del ScrollView
                Container(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Cerrar el diálogo primero
                        Navigator.of(context, rootNavigator: true).pop();
                        // Luego limpiar el formulario
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _limpiarFormulario();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _colorPrimario,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "ENTENDIDO",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Método auxiliar para filas más compactas
  Widget _buildInfoRowCompact(String titulo, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            titulo,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _colorTexto.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: _colorTexto,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _mostrarModalError(String mensaje) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_colorError, Color(0xFFF44336)],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Error al Registrar",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        mensaje,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: _colorTexto,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _colorError,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "ENTENDIDO",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
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
      },
    );
  }

  void _limpiarFormulario() {
    setState(() {
      _placaController.clear();
      _ubicacionController.clear();
      _observacionController.clear();
      _numeroComprobanteController.clear();
      _imagenesSeleccionadas.clear();
      _placaValida = false;
      _mensajeError = '';
      _subiendoEvidencias = false;
      _establecerFechaHoraActual();
      if (multas.isNotEmpty) {
        multaSeleccionada = multas.first;
        _totalController.text = multaSeleccionada!.valor.toStringAsFixed(2);
      }
    });
    _actualizarEstadoBoton();
  }

  @override
  void dispose() {
    _fechaEmisionController.dispose();
    _ubicacionController.dispose();
    _placaController.dispose();
    _totalController.dispose();
    _observacionController.dispose();
    _numeroComprobanteController.dispose();
    _placaFocusNode.dispose();
    _ubicacionFocusNode.dispose();
    _observacionFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
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
                    'Registrar Notificación',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Permite emitir multas de tránsito, registrar infracciones y generar comprobantes de impresión.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text(
          'Registrar Notificación',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
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
            icon: const Icon(Icons.info_outline, color: Colors.white),
            tooltip: 'Información',
            onPressed: () => _mostrarInfo(context),
          ),
          // Historial / reimprimir del día
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: 'Reimprimir multa',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReimpresionScreen()),
            ),
          ),
          // Indicador de estado de impresora
          EstadoImpresoraCompacto(onPressed: () => _mostrarSelectorImpresora()),
        ],
      ),
      floatingActionButton: null,
      body: cargando ? _buildCargando() : _buildContenidoPrincipal(),
    );
  }

  Widget _buildCargando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_colorPrimario, _colorPurple],
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
          Text(
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
            'Cargando datos...',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_colorPurple),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContenidoPrincipal() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  // --- Sección: Datos del vehículo ---
                  _buildSeccionCard(
                    titulo: 'Datos del Vehículo',
                    icono: Icons.directions_car_outlined,
                    children: [
                      _buildCampoPlaca(),
                      const SizedBox(height: 16),
                      _dropdownMulta(),
                      const SizedBox(height: 16),
                      _buildCampoTotal(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // --- Sección: Detalles de la multa ---
                  _buildSeccionCard(
                    titulo: 'Detalles de la Multa',
                    icono: Icons.description_outlined,
                    children: [
                      _buildCampoNumeroComprobante(),
                      const SizedBox(height: 16),
                      _buildCampoFechaHora(),
                      const SizedBox(height: 16),
                      _buildCampoUbicacion(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // --- Sección: Evidencias ---
                  _buildSeccionCard(
                    titulo: 'Evidencias y Observaciones',
                    icono: Icons.camera_alt_outlined,
                    children: [
                      _buildSeccionEvidencias(),
                      const SizedBox(height: 16),
                      _buildCampoObservacion(),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildBotonGuardar(),
        ],
      ),
    );
  }

  Widget _buildSeccionCard({
    required String titulo,
    required IconData icono,
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
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _colorPrimario.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, size: 18, color: _colorPrimario),
              ),
              const SizedBox(width: 10),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _colorPrimario,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1628), Color(0xFF000000)],
        ),
        boxShadow: [
          BoxShadow(
            color: _colorPrimario.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notification_add_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SIMERT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'Los campos (*) son obligatorios',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
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

  Widget _buildSeccionEvidencias() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Botones para agregar evidencias
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.photo_library, size: 20),
                label: Text("GALERÍA"),
                onPressed: _imagenesSeleccionadas.length < 3
                    ? _seleccionarImagenes
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: _colorPrimario),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.camera_alt, size: 20),
                label: Text("CÁMARA"),
                onPressed: _imagenesSeleccionadas.length < 3
                    ? _tomarFoto
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: _colorPrimario),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Grid de imágenes seleccionadas
        if (_imagenesSeleccionadas.isNotEmpty) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: _imagenesSeleccionadas.length,
            itemBuilder: (context, index) {
              return _buildItemImagen(index);
            },
          ),
          const SizedBox(height: 8),
          Text(
            "Toque una imagen para eliminarla. Se requieren exactamente 3 fotos.",
            style: TextStyle(
              fontSize: 12,
              color: _colorTexto.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: _colorFondo,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.photo_camera,
                  size: 50,
                  color: Colors.red.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  "Se requieren 3 evidencias fotográficas",
                  style: TextStyle(
                    color: Colors.red.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Use los botones de arriba para agregar fotos",
                  style: TextStyle(
                    color: _colorTexto.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Validación de evidencias
        if (_imagenesSeleccionadas.length != 3 &&
            _imagenesSeleccionadas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              "Faltan ${3 - _imagenesSeleccionadas.length} fotos. Se requieren exactamente 3.",
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemImagen(int index) {
    return GestureDetector(
      onTap: () => _eliminarImagen(index),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _colorBorde),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _imagenesSeleccionadas[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: _colorFondo,
                    child: Icon(Icons.error, color: _colorError),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoPlaca() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _placaController,
          focusNode: _placaFocusNode,
          decoration: InputDecoration(
            labelText: "Placa del vehículo *",
            hintText: "Ej: ABC1234 o AB123C",
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _colorBorde),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _colorPrimario, width: 2),
            ),
            suffixIcon: _placaController.text.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _placaValida
                          ? _colorPrimario.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                    ),
                    child: Icon(
                      _placaValida ? Icons.check_circle : Icons.error,
                      color: _placaValida ? _colorPrimario : Colors.red,
                      size: 20,
                    ),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          style: TextStyle(
            fontSize: 16,
            color: _colorTexto,
            fontWeight: FontWeight.w500,
          ),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            UpperCaseTextFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
            LengthLimitingTextInputFormatter(7),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return "La placa del vehículo es requerida";
            }
            final placaRegex = RegExp(r'^([A-Z]{3}\d{4}|[A-Z]{2}\d{3}[A-Z])$');
            if (!placaRegex.hasMatch(value)) {
              return "Formato inválido. Use ABC1234 o AB123C";
            }
            return null;
          },
        ),
        if (_placaController.text.isNotEmpty &&
            !_placaValida &&
            _mensajeError.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 12.0),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: _colorAcento),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    "Continue escribiendo... Formatos válidos: ABC1234 o AB123C",
                    style: TextStyle(color: _colorAcento, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCampoNumeroComprobante() {
    return TextFormField(
      controller: _numeroComprobanteController,
      decoration: InputDecoration(
        labelText: "Número de comprobante *",
        hintText: "Ej: 12345678 (mín. 2, máx. 8 dígitos)",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorPrimario, width: 2),
        ),
        prefixIcon: Icon(Icons.file_copy, color: _colorPrimario),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      style: TextStyle(fontSize: 16, color: _colorTexto),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8), // Máximo 8 dígitos
      ],
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "El número de comprobante es requerido";
        }
        if (value.length < 2) {
          return "El comprobante debe tener al menos 2 dígitos";
        }
        if (value.length > 8) {
          return "El comprobante no puede tener más de 8 dígitos";
        }
        if (!RegExp(r'^\d+$').hasMatch(value)) {
          return "Solo se permiten números";
        }
        return null;
      },
    );
  }

  Widget _buildCampoTotal() {
    return TextFormField(
      controller: _totalController,
      decoration: InputDecoration(
        labelText: "Valor total *",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorPrimario, width: 2),
        ),
        prefixIcon: Icon(Icons.attach_money, color: _colorPrimario),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      style: TextStyle(
        fontSize: 18,
        color: _colorPrimario,
        fontWeight: FontWeight.bold,
      ),
      readOnly: true,
      validator: (value) {
        if (value == null || value.isEmpty || value == "0.00") {
          return "Debe seleccionar un tipo de multa para generar el total";
        }
        return null;
      },
    );
  }

  Widget _buildCampoFechaHora() {
    return TextFormField(
      controller: _fechaEmisionController,
      decoration: InputDecoration(
        labelText: "Fecha y hora de emisión *",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorPrimario, width: 2),
        ),
        suffixIcon: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _colorPrimario.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            icon: Icon(Icons.calendar_today, color: _colorPrimario),
            onPressed: _seleccionarFechaHora,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      style: TextStyle(
        fontSize: 16,
        color: _colorTexto,
        fontWeight: FontWeight.w500,
      ),
      readOnly: true,
      onTap: _seleccionarFechaHora,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "La fecha y hora son requeridas";
        }
        try {
          final fecha = NotificacionService.parsearFechaHora(value);
          if (fecha.isAfter(DateTime.now())) {
            return "La fecha no puede ser futura";
          }
          return null;
        } catch (e) {
          return "Formato de fecha inválido";
        }
      },
    );
  }

  Widget _buildCampoUbicacion() {
    return TextFormField(
      controller: _ubicacionController,
      focusNode: _ubicacionFocusNode,
      decoration: InputDecoration(
        labelText: "Ubicación *",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorPrimario, width: 2),
        ),
        prefixIcon: Icon(Icons.location_on, color: _colorPrimario),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      style: TextStyle(fontSize: 16, color: _colorTexto),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "La ubicación es requerida";
        }
        if (value.length < 3) {
          return "La ubicación debe tener al menos 3 caracteres";
        }
        return null;
      },
    );
  }

  Widget _buildCampoObservacion() {
    return TextFormField(
      controller: _observacionController,
      focusNode: _observacionFocusNode,
      decoration: InputDecoration(
        labelText: "Observaciones *",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorPrimario, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      keyboardType: TextInputType.multiline,
      maxLines: 4,
      style: TextStyle(fontSize: 16, color: _colorTexto),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "Las observaciones son requeridas";
        }
        if (value.length < 5) {
          return "Las observaciones deben tener al menos 10 caracteres";
        }
        return null;
      },
    );
  }

  Widget _buildBotonGuardar() {
    // Validación simplificada pero completa
    bool placaOk = _placaValida;
    bool multaOk = multaSeleccionada != null;
    bool comprobanteOk =
        _numeroComprobanteController.text.length >= 2 &&
        _numeroComprobanteController.text.length <= 8;
    bool fechaOk = _fechaEmisionController.text.isNotEmpty;
    bool ubicacionOk = _ubicacionController.text.length >= 3;
    bool observacionOk = _observacionController.text.length >= 10;
    bool fotosOk = _imagenesSeleccionadas.length == 3;

    bool formularioCompleto =
        placaOk &&
        multaOk &&
        comprobanteOk &&
        fechaOk &&
        ubicacionOk &&
        observacionOk &&
        fotosOk;

    final bool puedeGuardar = formularioCompleto && !_subiendoEvidencias;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indicador de progreso del formulario
              _buildProgresoFormulario(
                placaOk,
                multaOk,
                comprobanteOk,
                fechaOk,
                ubicacionOk,
                observacionOk,
                fotosOk,
              ),
              const SizedBox(height: 10),
              // Botón guardar (ancho completo)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: puedeGuardar
                        ? const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xFF0A1628), Color(0xFF000000)],
                          )
                        : null,
                    color: puedeGuardar ? null : Colors.grey[300],
                    boxShadow: puedeGuardar
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF0A1628,
                              ).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: ElevatedButton.icon(
                    icon: _subiendoEvidencias
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
                        : const Icon(
                            Icons.save_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                    label: Text(
                      _subiendoEvidencias ? 'SUBIENDO...' : 'GUARDAR MULTA',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: puedeGuardar ? _guardarMulta : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgresoFormulario(
    bool placa,
    bool multa,
    bool comprobante,
    bool fecha,
    bool ubicacion,
    bool observacion,
    bool fotos,
  ) {
    final items = [
      placa,
      multa,
      comprobante,
      fecha,
      ubicacion,
      observacion,
      fotos,
    ];
    final completados = items.where((v) => v).length;
    final total = items.length;
    final progreso = completados / total;
    final todoCompleto = completados == total;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 6,
              backgroundColor: const Color(0xFFE8EAF0),
              valueColor: AlwaysStoppedAnimation<Color>(
                todoCompleto
                    ? const Color(0xFF00C853)
                    : const Color(0xFF0A1628),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          todoCompleto ? 'Listo' : '$completados/$total',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: todoCompleto
                ? const Color(0xFF00C853)
                : const Color(0xFF0A1628),
          ),
        ),
      ],
    );
  }

  Future<void> _imprimirMulta() async {
    // Imprimir la multa usando el gestor
    bool resultado = await _gestorImpresora.imprimirMultaConDialogo(
      context: context,
      placa: _placaController.text,
      tipoMulta: multaSeleccionada?.detalleMulta ?? "Sin especificar",
      valor: multaSeleccionada?.valor ?? 0.0,
      fechaEmision: _fechaEmisionController.text,
      ubicacion: _ubicacionController.text,
      numeroComprobante: _numeroComprobanteController.text,
      observacion: _observacionController.text,
      usuario: name.isNotEmpty ? name.toUpperCase() : "OPERADOR",
      idNotificacion: 0, // Se actualizará después de guardar
    );

    if (resultado) {
      mostrarNotificacionImpresora(
        context,
        mensaje: "Ticket impreso exitosamente",
        esError: false,
      );
    }
  }

  Widget _dropdownMulta() {
    return DropdownButtonFormField<Multa>(
      isExpanded: true,
      decoration: InputDecoration(
        labelText: "Tipo de multa *",
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _colorPrimario, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      initialValue: multaSeleccionada,
      items: multas
          .map(
            (m) => DropdownMenuItem(
              value: m,
              child: Text(
                "${m.detalleMulta} (\$${m.valor.toStringAsFixed(2)})",
                style: TextStyle(fontSize: 14, color: _colorTexto),
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          multaSeleccionada = value;
          if (value != null) {
            _totalController.text = value.valor.toStringAsFixed(2);
          }
        });
        _actualizarEstadoBoton();
      },
      style: TextStyle(fontSize: 14, color: _colorTexto),
      validator: (value) {
        if (value == null) {
          return "Debe seleccionar un tipo de multa";
        }
        return null;
      },
    );
  }

  /// Mostrar diálogo para seleccionar impresora
  Future<void> _mostrarSelectorImpresora() async {
    final resultado = await mostrarDialogoConectarImpresora(context);
    if (resultado == true && mounted) {
      setState(() {});
      _mostrarSnackBar('Impresora seleccionada correctamente');
    }
  }

  /// Imprime por Bluetooth si hay impresora conectada, o guarda PDF si no la hay
  Future<String> _procesarImpresionOPdf(int idNotificacion) async {
    if (_gestorImpresora.estaConectada) {
      final impreso = await _gestorImpresora.imprimirMultaSilenciosa(
        placa: _placaController.text,
        tipoMulta: multaSeleccionada?.detalleMulta ?? 'Sin especificar',
        valor: multaSeleccionada?.valor ?? 0.0,
        fechaEmision: _fechaEmisionController.text,
        ubicacion: _ubicacionController.text,
        numeroComprobante: _numeroComprobanteController.text,
        observacion: _observacionController.text,
        usuario: name.isNotEmpty ? name.toUpperCase() : 'OPERADOR',
        idNotificacion: idNotificacion,
      );
      return impreso
          ? 'Ticket enviado a la impresora correctamente.'
          : 'No se pudo enviar a la impresora.';
    } else {
      final ruta = await _guardarMultaComoPdf(idNotificacion);
      return ruta != null
          ? 'PDF guardado en:\n$ruta'
          : 'No se pudo guardar el PDF.';
    }
  }

  /// Genera y guarda la multa como archivo PDF en el dispositivo
  Future<String?> _guardarMultaComoPdf(int idNotificacion) async {
    try {
      final doc = pw.Document();
      final placa = _placaController.text;
      final tipoMulta = multaSeleccionada?.detalleMulta ?? 'Sin especificar';
      final valor = multaSeleccionada?.valor ?? 0.0;
      final fecha = _fechaEmisionController.text;
      final ubicacion = _ubicacionController.text;
      final comprobante = _numeroComprobanteController.text;
      final observacion = _observacionController.text;
      final operador = name.isNotEmpty ? name.toUpperCase() : 'OPERADOR';

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
              _pdfFila('Operador:', operador),
            ],
          ),
        ),
      );

      final bytes = await doc.save();

      final Directory dir;
      if (Platform.isAndroid) {
        final downloads = Directory('/storage/emulated/0/Download');
        dir = await downloads.exists()
            ? downloads
            : await getApplicationDocumentsDirectory();
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

  /// Construye una fila etiqueta-valor para el PDF
  pw.Widget _pdfFila(String label, String value) {
    return pw.Padding(
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
  }
}

import 'dart:io';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import '../../servicios/servicioImpresionTermica.dart';

/// Widget flotante para acceso rápido a la impresora
class FloatingImpresoraButton extends StatefulWidget {
  final VoidCallback? onImpresora;
  final Color? backgroundColor;

  const FloatingImpresoraButton({
    super.key,
    this.onImpresora,
    this.backgroundColor,
  });

  @override
  State<FloatingImpresoraButton> createState() =>
      _FloatingImpresoraButtonState();
}

class _FloatingImpresoraButtonState extends State<FloatingImpresoraButton>
    with SingleTickerProviderStateMixin {
  final ServicioImpresionTermica _servicio = ServicioImpresionTermica();
  late AnimationController _animationController;
  bool _conectado = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _verificarConexion();

    // Verificar cada 2 segundos
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 2));
      _verificarConexion();
      return mounted;
    });
  }

  void _verificarConexion() {
    setState(() {
      _conectado = _servicio.estaConectado;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: widget.onImpresora,
      backgroundColor:
          widget.backgroundColor ??
          (_conectado ? Colors.green[600] : Colors.grey[600]),
      tooltip: _conectado ? 'Impresora conectada' : 'Conectar impresora',
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.print),
          if (_conectado)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget de estado compacto para mostrar en AppBar
class EstadoImpresoraCompacto extends StatefulWidget {
  final VoidCallback? onPressed;

  const EstadoImpresoraCompacto({super.key, this.onPressed});

  @override
  State<EstadoImpresoraCompacto> createState() =>
      _EstadoImpresoraCompactoState();
}

class _EstadoImpresoraCompactoState extends State<EstadoImpresoraCompacto> {
  final ServicioImpresionTermica _servicio = ServicioImpresionTermica();
  bool _conectado = false;

  @override
  void initState() {
    super.initState();
    _verificarConexion();

    // Verificar cada 3 segundos
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 3));
      _verificarConexion();
      return mounted;
    });
  }

  void _verificarConexion() {
    setState(() {
      _conectado = _servicio.estaConectado;
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.print,
              color: _conectado ? Colors.green : Colors.red,
              size: 18,
            ),
            SizedBox(width: 4),
            Text(
              _conectado ? 'Conectada' : 'Desconectada',
              style: TextStyle(
                fontSize: 12,
                color: _conectado ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog para seleccionar y conectar impresora
Future<bool?> mostrarDialogoConectarImpresora(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _DialogoConectarImpresora(),
  );
}

class _DialogoConectarImpresora extends StatefulWidget {
  @override
  State<_DialogoConectarImpresora> createState() =>
      _DialogoConectarImpresoraState();
}

class _DialogoConectarImpresoraState extends State<_DialogoConectarImpresora> {
  final ServicioImpresionTermica _servicio = ServicioImpresionTermica();
  final bool _esWindows = Platform.isWindows;
  bool _cargando = false;
  List<dynamic> _dispositivos = <dynamic>[];
  List<String> _puertosUSB = [];
  BluetoothDevice? _dispositivoGuardado;
  String? _puertoGuardado;
  bool _mostrandoGuardado = false;

  @override
  void initState() {
    super.initState();
    _cargarEstadoInicial();
  }

  Future<void> _cargarEstadoInicial() async {
    setState(() => _cargando = true);
    try {
      if (_esWindows) {
        final config = await _servicio.obtenerConfiguracionGuardada();
        if (config['printer_type'] == 'usb' &&
            (config['printer_port'] ?? '').isNotEmpty) {
          if (mounted) {
            setState(() {
              _puertoGuardado = config['printer_port'];
              _mostrandoGuardado = true;
              _cargando = false;
            });
          }
        } else {
          _listarPuertosUSB();
        }
      } else {
        final guardado = await _servicio.obtenerDispositivoGuardado();
        if (guardado != null && mounted) {
          setState(() {
            _dispositivoGuardado = guardado;
            _mostrandoGuardado = true;
            _cargando = false;
          });
        } else {
          _escanearDispositivos();
        }
      }
    } catch (_) {
      if (_esWindows) {
        _listarPuertosUSB();
      } else {
        _escanearDispositivos();
      }
    }
  }

  Future<void> _cambiarImpresora() async {
    await _servicio.limpiarConfiguracion();
    setState(() {
      _dispositivoGuardado = null;
      _puertoGuardado = null;
      _mostrandoGuardado = false;
    });
    if (_esWindows) {
      _listarPuertosUSB();
    } else {
      _escanearDispositivos();
    }
  }

  Future<void> _listarPuertosUSB() async {
    setState(() => _cargando = true);
    try {
      final puertos = await _servicio.listarPuertosUSB();
      if (mounted) {
        setState(() {
          _puertosUSB = puertos;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _conectarUSB(String puerto) async {
    setState(() => _cargando = true);
    try {
      final exitoso = await _servicio.conectarPuertoUSB(puerto);
      if (!mounted) return;
      if (exitoso) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conectado a $puerto'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir el puerto. Verifica que la impresora esté conectada.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _escanearDispositivos() async {
    setState(() => _cargando = true);

    try {
      final dispositivos = await _servicio.escanearDispositivos();
      setState(() {
        _dispositivos = dispositivos;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _conectar(dispositivo) async {
    setState(() => _cargando = true);

    try {
      bool exitoso = await _servicio.conectarDispositivo(dispositivo);

      if (exitoso) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conectado a ${dispositivo.name}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo conectar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _cargando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildVistaVinculadaUSB() {
    final puerto = _puertoGuardado!;
    final yaConectado = _servicio.estaConectado;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: yaConectado
                  ? Colors.green.shade50
                  : const Color(0xFFF0F4FF),
              shape: BoxShape.circle,
              border: Border.all(
                color: yaConectado
                    ? Colors.green.shade300
                    : const Color(0xFF001F54).withValues(alpha: 0.20),
                width: 2,
              ),
            ),
            child: Icon(
              yaConectado ? Icons.usb : Icons.usb_outlined,
              size: 36,
              color: yaConectado
                  ? Colors.green.shade700
                  : const Color(0xFF001F54),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Impresora USB',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            puerto,
            style: const TextStyle(fontSize: 13, color: Color(0xFF777777)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: yaConectado ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              yaConectado ? 'Conectada' : 'Vinculada',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: yaConectado
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cargando ? null : () => _conectarUSB(puerto),
              icon: _cargando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.usb, size: 18),
              label: Text(yaConectado ? 'Reconectar' : 'Conectar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF001F54),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cargando ? null : _cambiarImpresora,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Cambiar puerto'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5E17EB),
                side: const BorderSide(color: Color(0xFF5E17EB), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildVistaVinculada() {
    final d = _dispositivoGuardado!;
    final yaConectado = _servicio.estaConectado;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: yaConectado
                  ? Colors.green.shade50
                  : const Color(0xFFF0F4FF),
              shape: BoxShape.circle,
              border: Border.all(
                color: yaConectado
                    ? Colors.green.shade300
                    : const Color(0xFF001F54).withValues(alpha: 0.20),
                width: 2,
              ),
            ),
            child: Icon(
              yaConectado ? Icons.print : Icons.print_outlined,
              size: 36,
              color: yaConectado
                  ? Colors.green.shade700
                  : const Color(0xFF001F54),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            d.name ?? 'Impresora',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            d.address ?? '',
            style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: yaConectado ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              yaConectado ? 'Conectada' : 'Vinculada',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: yaConectado
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cargando ? null : () => _conectar(d),
              icon: _cargando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.bluetooth_connected, size: 18),
              label: Text(yaConectado ? 'Reconectar' : 'Conectar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF001F54),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cargando ? null : _cambiarImpresora,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Cambiar impresora'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5E17EB),
                side: const BorderSide(color: Color(0xFF5E17EB), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: screenHeight * 0.75),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Encabezado con gradiente
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF001F54), Color(0xFF5E17EB)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.print,
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
                          _esWindows ? 'Impresora USB' : 'Impresora Bluetooth',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _mostrandoGuardado
                              ? (_esWindows
                                    ? 'Puerto guardado'
                                    : 'Impresora vinculada')
                              : (_esWindows
                                    ? 'Selecciona el puerto COM'
                                    : 'Selecciona un dispositivo para conectar'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Cuerpo
            Flexible(
              child: _cargando
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF001F54),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Buscando dispositivos...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF555555),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _mostrandoGuardado &&
                        (_dispositivoGuardado != null ||
                            _puertoGuardado != null)
                  ? (_esWindows
                        ? _buildVistaVinculadaUSB()
                        : _buildVistaVinculada())
                  : _esWindows
                  ? (_puertosUSB.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 20,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F4FF),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(
                                        0xFF001F54,
                                      ).withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.usb_off,
                                    size: 30,
                                    color: Color(0xFF001F54),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No se encontraron puertos COM',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Conecta la impresora por USB y aseg\u00farate de que el driver est\u00e9 instalado.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF777777),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _listarPuertosUSB,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Volver a buscar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF001F54),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _puertosUSB.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 56),
                            itemBuilder: (context, index) {
                              final puerto = _puertosUSB[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 4,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF0F4FF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    puerto.startsWith('USB')
                                        ? Icons.usb
                                        : Icons.cable,
                                    color: const Color(0xFF001F54),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  puerto,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                                subtitle: Text(
                                  puerto.startsWith('USB')
                                      ? 'Puerto USB directo'
                                      : puerto.startsWith('COM')
                                      ? 'Puerto serie (COM)'
                                      : 'Puerto paralelo (LPT)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF777777),
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFF001F54),
                                ),
                                onTap: () => _conectarUSB(puerto),
                              );
                            },
                          ))
                  : _dispositivos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4FF),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(
                                  0xFF001F54,
                                ).withValues(alpha: 0.15),
                              ),
                            ),
                            child: const Icon(
                              Icons.print_disabled_outlined,
                              size: 30,
                              color: Color(0xFF001F54),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No se encontraron impresoras',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Aseg\u00farate de que el Bluetooth est\u00e9 activo y la impresora encendida.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF777777),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _escanearDispositivos,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Volver a escanear'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF001F54),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _dispositivos.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (context, index) {
                        final dispositivo = _dispositivos[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.print_outlined,
                              color: Color(0xFF001F54),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            dispositivo.name ?? 'Desconocido',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF333333),
                            ),
                          ),
                          subtitle: Text(
                            dispositivo.address ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF777777),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Color(0xFF001F54),
                          ),
                          onTap: () => _conectar(dispositivo),
                        );
                      },
                    ),
            ),
            // Footer con botón actualizar (solo cuando hay lista)
            if (!_cargando &&
                !_mostrandoGuardado &&
                (_esWindows
                    ? _puertosUSB.isNotEmpty
                    : _dispositivos.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _esWindows
                        ? _listarPuertosUSB
                        : _escanearDispositivos,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(
                      _esWindows ? 'Actualizar puertos' : 'Volver a escanear',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF001F54),
                      side: const BorderSide(
                        color: Color(0xFF001F54),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Snackbar de notificación de impresora
void mostrarNotificacionImpresora(
  BuildContext context, {
  required String mensaje,
  bool esError = false,
  Duration duracion = const Duration(seconds: 2),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(esError ? Icons.error : Icons.check_circle, color: Colors.white),
          SizedBox(width: 12),
          Expanded(child: Text(mensaje)),
        ],
      ),
      backgroundColor: esError ? Colors.red[700] : Colors.green[700],
      duration: duracion,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.all(16),
    ),
  );
}

/// Widget indicador de estado de impresora para colocar en cualquier lado
class IndicadorEstadoImpresora extends StatefulWidget {
  final bool mostrarTexto;
  final double size;

  const IndicadorEstadoImpresora({
    super.key,
    this.mostrarTexto = true,
    this.size = 24,
  });

  @override
  State<IndicadorEstadoImpresora> createState() =>
      _IndicadorEstadoImpresoraState();
}

class _IndicadorEstadoImpresoraState extends State<IndicadorEstadoImpresora> {
  final ServicioImpresionTermica _servicio = ServicioImpresionTermica();
  bool _conectado = false;

  @override
  void initState() {
    super.initState();
    _verificarConexion();

    // Verificar cada 2 segundos
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 2));
      _verificarConexion();
      return mounted;
    });
  }

  void _verificarConexion() {
    setState(() {
      _conectado = _servicio.estaConectado;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _conectado ? Colors.green : Colors.red,
            boxShadow: [
              if (_conectado)
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
            ],
          ),
        ),
        if (widget.mostrarTexto) ...[
          SizedBox(width: 6),
          Text(
            _conectado ? 'Impresora OK' : 'Sin impresora',
            style: TextStyle(
              fontSize: 12,
              color: _conectado ? Colors.green[700] : Colors.red[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

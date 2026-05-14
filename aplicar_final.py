#!/usr/bin/env python3
"""
Aplica cambios finales:
A. _ejecutarLiberacion() - liberacion local definitiva SIN reversion
B. _mostrarErrorModal() - nuevo metodo
C. _mensajeErrorLiberacion() - nuevo metodo
D. _liberarEstacionamientoExpirado() - mejorar error con modal
E. Error en registro - modal en lugar de SnackBar
F. _mensajeErrorRegistro() - nuevo metodo
"""
FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

original = content
results = []

# ============================================================
# CAMBIO A: _ejecutarLiberacion() - liberacion local definitiva
# ============================================================
old_a = """  /// Ejecuta la liberación completa de un estacionamiento (llamado desde el botón Liberar).
  void _ejecutarLiberacion(int estacionId) {
    unawaited((() async {
      setState(() {
        _estacionamientosLiberando[estacionId] = true;
      });

      final tarjetaPrevia = _estacionamientosTarjeta
          .where((t) => t.estacionId == estacionId)
          .toList();

      _enProceso.add(estacionId);

      try {
        _updateUIAfterChange(estacionId, false, '');
        setState(() {
          _estacionamientosTarjeta.removeWhere(
            (t) => t.estacionId == estacionId,
          );
        });
        await _persistirCacheCompleto();
        await actualizarRegistro(
          estacionId: estacionId,
          placa: '',
          estado: false,
          token: _token,
        );
        _fetchAndCacheEstacionamientosTarjeta();
        _showCustomSnackBar(
          'Estacionamiento #${_estaciones.firstWhere(
            (e) => e.id == estacionId,
            orElse: () => _estaciones.isNotEmpty ? _estaciones.first : Estacionamiento(id: 0, numero: 0, direccion: '', placa: '', estado: false),
          ).numero} liberado correctamente',
        );
      } catch (e) {
        _updateUIAfterChange(estacionId, true, '');
        setState(() {
          _estacionamientosTarjeta.addAll(tarjetaPrevia);
        });
        unawaited(_persistirCacheCompleto());
        _showCustomSnackBar('Error al liberar: $e', isError: true);
      } finally {
        if (mounted) {
          setState(() {
            _estacionamientosLiberando.remove(estacionId);
          });
        }
        Future.delayed(
          const Duration(seconds: 2),
          () => _enProceso.remove(estacionId),
        );
      }
    })());
  }"""

new_a = """  /// Ejecuta la liberación completa de un estacionamiento (llamado desde el botón Liberar).
  /// La liberación LOCAL es DEFINITIVA: nunca se revierte aunque el servidor falle.
  /// Si el servidor falla, se muestra un modal con el error pero la UI no se revierte.
  void _ejecutarLiberacion(int estacionId) {
    unawaited((() async {
      setState(() {
        _estacionamientosLiberando[estacionId] = true;
      });

      _enProceso.add(estacionId);

      // 1. LIBERAR LOCAL INMEDIATAMENTE (siempre, sin importar el servidor)
      _updateUIAfterChange(estacionId, false, '');
      setState(() {
        _estacionamientosTarjeta.removeWhere(
          (t) => t.estacionId == estacionId,
        );
      });
      await _persistirCacheInmediato();
      _enviarTarjetasAlServicioNativo();

      // 2. SINCRONIZAR CON SERVIDOR EN BACKGROUND
      // Si falla, NO se revierte la UI. Solo se muestra un modal de error.
      try {
        await actualizarRegistro(
          estacionId: estacionId,
          placa: '',
          estado: false,
          token: _token,
        );
        _fetchAndCacheEstacionamientosTarjeta();
      } catch (e) {
        _mostrarErrorModal(_mensajeErrorLiberacion(e));
      } finally {
        if (mounted) {
          setState(() {
            _estacionamientosLiberando.remove(estacionId);
          });
        }
        Future.delayed(
          const Duration(seconds: 2),
          () => _enProceso.remove(estacionId),
        );
      }
    })());
  }"""

count_a = content.count(old_a)
results.append(f"Cambio A: {count_a} ocurrencias")
if count_a == 1:
    content = content.replace(old_a, new_a)
    results[-1] += " -> APLICADO"
else:
    results[-1] += f" -> ERROR"

# ============================================================
# CAMBIO D: _liberarEstacionamientoExpirado() - mejorar error con modal
# ============================================================
old_d = """      } catch (e) {
        debugPrint('[ADVERTENCIA]  Error al liberar en servidor: $e');
      }"""

new_d = """      } catch (e) {
        debugPrint('[ADVERTENCIA]  Error al liberar en servidor: $e');
        _mostrarErrorModal(_mensajeErrorLiberacion(e));
      }"""

count_d = content.count(old_d)
results.append(f"Cambio D: {count_d} ocurrencias")
if count_d == 1:
    content = content.replace(old_d, new_d)
    results[-1] += " -> APLICADO"
else:
    results[-1] += f" -> ERROR"

# ============================================================
# CAMBIO E: Error en registro - modal en lugar de SnackBar
# ============================================================
old_e = """                                            _showCustomSnackBar(
                                              '[X]  Error al sincronizar con el servidor: $e',
                                              isError: true,
                                            );"""

new_e = """                                            _mostrarErrorModal(_mensajeErrorRegistro(e));"""

count_e = content.count(old_e)
results.append(f"Cambio E: {count_e} ocurrencias")
if count_e == 1:
    content = content.replace(old_e, new_e)
    results[-1] += " -> APLICADO"
else:
    results[-1] += f" -> ERROR"

# ============================================================
# CAMBIOS B, C, F: Insertar metodos nuevos despues de _showCustomSnackBar
# Buscar el cierre de _showCustomSnackBar (el ultimo } antes de _CountdownTicker)
# ============================================================
# Insertar despues del cierre de _showCustomSnackBar y antes del siguiente metodo
old_metodos = "\n  void _cambiarFiltroTab(int index) {"
new_metodos = """

  /// Muestra un modal de error que el usuario debe cerrar explícitamente.
  /// A diferencia de _showCustomSnackBar, este modal no desaparece solo.
  void _mostrarErrorModal(String mensaje) {
    if (!mounted || _appEnSegundoPlano) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFD32F2F), size: 24),
            const SizedBox(width: 10),
            const Text('Error', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(mensaje, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Traduce errores de liberación a mensajes claros para el usuario.
  String _mensajeErrorLiberacion(dynamic error) {
    final msg = error.toString();
    if (msg.contains('SocketException') ||
        msg.contains('HandshakeException') ||
        msg.contains('TimeoutException') ||
        msg.contains('sin conexión')) {
      return 'No se pudo conectar con el servidor para liberar el estacionamiento.\n\n'
          'El estacionamiento ya fue liberado localmente. '
          'Los cambios se sincronizarán automáticamente cuando la conexión se restablezca.';
    }
    if (msg.contains('409') || msg.contains('Conflict')) {
      return 'El estacionamiento ya fue liberado por otro usuario.\n\n'
          'No es necesario realizar ninguna acción adicional.';
    }
    if (msg.contains('401') || msg.contains('No autorizado')) {
      return 'Su sesión ha expirado. Por favor, cierre sesión y vuelva a iniciarla.';
    }
    final msgCorto = msg.length > 200 ? msg.substring(0, 200) : msg;
    return 'Ocurrió un error al liberar el estacionamiento: $msgCorto\n\n'
        'El estacionamiento ya fue liberado localmente. '
        'Si el problema persiste, contacte al administrador.';
  }

  /// Traduce errores de registro a mensajes claros para el usuario.
  String _mensajeErrorRegistro(dynamic error) {
    final msg = error.toString();
    if (msg.contains('SocketException') ||
        msg.contains('HandshakeException') ||
        msg.contains('TimeoutException')) {
      return 'No se pudo conectar con el servidor para registrar el estacionamiento.\n\n'
          'El registro se ha guardado localmente. '
          'Los cambios se sincronizarán automáticamente cuando la conexión se restablezca.';
    }
    if (msg.contains('409') || msg.contains('Conflict')) {
      return 'Este estacionamiento ya fue registrado por otro usuario.\n\n'
          'Por favor, seleccione otro espacio disponible.';
    }
    if (msg.contains('400')) {
      return 'Los datos ingresados no son válidos.\n\n'
          'Verifique que la placa y el número de tarjeta sean correctos.';
    }
    final msgCorto = msg.length > 200 ? msg.substring(0, 200) : msg;
    return 'Ocurrió un error al registrar: $msgCorto';
  }

  void _cambiarFiltroTab(int index) {"""

count_metodos = content.count(old_metodos)
results.append(f"Insertar metodos B/C/F: {count_metodos} ocurrencias")
if count_metodos == 1:
    content = content.replace(old_metodos, new_metodos)
    results[-1] += " -> APLICADO"
else:
    results[-1] += f" -> ERROR"

# ============================================================
# Guardar
# ============================================================
if content != original:
    with open(FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Archivo guardado exitosamente.")
else:
    print("ADVERTENCIA: No se realizaron cambios!")

print("\n--- Resumen de cambios ---")
for r in results:
    print(f"  {r}")

#!/usr/bin/env python3
"""Aplica solo el Cambio A: _ejecutarLiberacion() liberacion local definitiva."""
FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

# El bloque exacto a reemplazar (usando raw string para evitar problemas con $)
old = (
    '  void _ejecutarLiberacion(int estacionId) {\n'
    '    unawaited((() async {\n'
    '      setState(() {\n'
    '        _estacionamientosLiberando[estacionId] = true;\n'
    '      });\n'
    '\n'
    '      final tarjetaPrevia = _estacionamientosTarjeta\n'
    '          .where((t) => t.estacionId == estacionId)\n'
    '          .toList();\n'
    '\n'
    '      _enProceso.add(estacionId);\n'
    '\n'
    '      try {\n'
    "        _updateUIAfterChange(estacionId, false, '');\n"
    '        setState(() {\n'
    '          _estacionamientosTarjeta.removeWhere(\n'
    '            (t) => t.estacionId == estacionId,\n'
    '          );\n'
    '        });\n'
    '        await _persistirCacheCompleto();\n'
    '        await actualizarRegistro(\n'
    '          estacionId: estacionId,\n'
    "          placa: '',\n"
    '          estado: false,\n'
    '          token: _token,\n'
    '        );\n'
    '        _fetchAndCacheEstacionamientosTarjeta();\n'
    '        _showCustomSnackBar(\n'
    "          'Estacionamiento #${_estaciones.firstWhere(\n"
    '            (e) => e.id == estacionId,\n'
    "            orElse: () => _estaciones.isNotEmpty ? _estaciones.first : Estacionamiento(id: 0, numero: 0, direccion: '', placa: '', estado: false),\n"
    '          ).numero} liberado correctamente\',\n'
    '        );\n'
    '      } catch (e) {\n'
    "        _updateUIAfterChange(estacionId, true, '');\n"
    '        setState(() {\n'
    '          _estacionamientosTarjeta.addAll(tarjetaPrevia);\n'
    '        });\n'
    '        unawaited(_persistirCacheCompleto());\n'
    "        _showCustomSnackBar('Error al liberar: $e', isError: true);\n"
    '      } finally {\n'
    '        if (mounted) {\n'
    '          setState(() {\n'
    '            _estacionamientosLiberando.remove(estacionId);\n'
    '          });\n'
    '        }\n'
    '        Future.delayed(\n'
    '          const Duration(seconds: 2),\n'
    '          () => _enProceso.remove(estacionId),\n'
    '        );\n'
    '      }\n'
    '    })());\n'
    '  }'
)

new_a = (
    '  void _ejecutarLiberacion(int estacionId) {\n'
    '    unawaited((() async {\n'
    '      setState(() {\n'
    '        _estacionamientosLiberando[estacionId] = true;\n'
    '      });\n'
    '\n'
    '      _enProceso.add(estacionId);\n'
    '\n'
    '      // 1. LIBERAR LOCAL INMEDIATAMENTE (siempre, sin importar el servidor)\n'
    "      _updateUIAfterChange(estacionId, false, '');\n"
    '      setState(() {\n'
    '        _estacionamientosTarjeta.removeWhere(\n'
    '          (t) => t.estacionId == estacionId,\n'
    '        );\n'
    '      });\n'
    '      await _persistirCacheInmediato();\n'
    '\n'
    '      // 2. SINCRONIZAR CON SERVIDOR EN BACKGROUND\n'
    '      // Si falla, NO se revierte la UI. Solo se muestra un modal de error.\n'
    '      try {\n'
    '        await actualizarRegistro(\n'
    '          estacionId: estacionId,\n'
    "          placa: '',\n"
    '          estado: false,\n'
    '          token: _token,\n'
    '        );\n'
    '        _fetchAndCacheEstacionamientosTarjeta();\n'
    '      } catch (e) {\n'
    '        _mostrarErrorModal(_mensajeErrorLiberacion(e));\n'
    '      } finally {\n'
    '        if (mounted) {\n'
    '          setState(() {\n'
    '            _estacionamientosLiberando.remove(estacionId);\n'
    '          });\n'
    '        }\n'
    '        Future.delayed(\n'
    '          const Duration(seconds: 2),\n'
    '          () => _enProceso.remove(estacionId),\n'
    '        );\n'
    '      }\n'
    '    })());\n'
    '  }'
)

count = content.count(old)
print(f"Cambio A: {count} ocurrencias encontradas")

if count == 1:
    content = content.replace(old, new_a)
    with open(FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    print("OK - Cambio A aplicado")
else:
    print(f"ERROR: se esperaba 1, se encontraron {count}")
    # Mostrar primeros 50 chars de cada ocurrencia
    idx = 0
    for i in range(count):
        idx = content.find(old, idx)
        if idx >= 0:
            print(f"  [{i}] en indice {idx}: ...{content[idx:idx+80]}...")
            idx += 1

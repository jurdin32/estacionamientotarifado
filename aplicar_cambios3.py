#!/usr/bin/env python3
"""
Corrige el bug: unawaited(() async { ... }()) no ejecuta la sincronizacion.
Lo reemplaza por una llamada directa a _sincronizarRegistroConServidor.
"""
FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

# El bloque exacto a reemplazar (desde "// 3. Sincronizar" hasta "}());")
old_block = """                                      // 3. Sincronizar con el servidor en background
                                      unawaited(() async {
                                        try {
                                          // Ejecutar registro de tarjeta y actualización de estación
                                          // en PARALELO para que el broadcast WS salga más rápido
                                          await Future.wait([
                                            registarEstacionamientoTarjeta(
                                              nuevoRegistro,
                                              token: _token,
                                            ),
                                            actualizarRegistro(
                                              estacionId: estacionCapturado.id,
                                              placa: placa,
                                              estado: true,
                                              token: _token,
                                            ),
                                          ]);
                                          // Actualizar tiempo de tarjeta después
                                          final totalConsumido =
                                              _minutosConsumidosTarjeta(
                                                tarjeta,
                                              );
                                          unawaited(
                                            actualizarTiempoTarjeta(
                                              tarjeta,
                                              totalConsumido,
                                              token: _token,
                                            ),
                                          );
                                          // Mantener guardia 2s para que el WS
                                          // broadcast llegue a otros dispositivos
                                          Future.delayed(
                                            const Duration(seconds: 2),
                                            () => _enProceso.remove(
                                              estacionCapturado.id,
                                            ),
                                          );
                                          _fetchAndCacheEstacionamientosTarjeta();
                                        } catch (e) {
                                          // Revertir si el servidor falla
                                          _enProceso.remove(
                                            estacionCapturado.id,
                                          );
                                          if (mounted) {
                                            _updateUIAfterChange(
                                              estacionCapturado.id,
                                              false,
                                              '',
                                            );
                                            setState(() {
                                              _estacionamientosTarjeta
                                                  .removeWhere(
                                                    (t) =>
                                                        t.estacionId ==
                                                        estacionCapturado.id,
                                                  );
                                            });
                                            unawaited(
                                              _persistirCacheCompleto(),
                                            );
                                            _showCustomSnackBar(
                                              '[X]  Error al sincronizar con el servidor: $e',
                                              isError: true,
                                            );
                                          }
                                        }
                                      }());"""

new_block = """                                      // 3. Sincronizar con el servidor en background
                                      unawaited(_sincronizarRegistroConServidor(
                                        nuevoRegistro,
                                        estacionCapturado,
                                        placa,
                                        tarjeta,
                                      ));"""

count = content.count(old_block)
print(f"Bloque a reemplazar: {count} ocurrencias")

if count == 1:
    content = content.replace(old_block, new_block)
    with open(FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    print("OK - Reemplazo aplicado")
else:
    print(f"ERROR: se esperaba 1, se encontraron {count}")
    # Mostrar los primeros 200 chars de cada ocurrencia
    idx = 0
    for i in range(count):
        idx = content.find(old_block, idx)
        if idx >= 0:
            print(f"  Ocurrencia {i+1} en indice {idx}: ...{content[idx:idx+100]}...")
            idx += 1

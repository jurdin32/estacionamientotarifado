e e$path = "lib/tarjetas/views/EstacionamientoScreen.dart"
$lines = Get-Content $path

# Find the start and end of the old _sincronizarRegistroServidor method
$startLine = -1
$endLine = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "/// Sincroniza el registro de estacionamiento con el servidor en background.") {
        $startLine = $i
    }
    if ($startLine -ge 0 -and $lines[$i] -match "^\s+\}" -and ($i - $startLine) -gt 30) {
        # Check if next line is a method or field declaration
        if ($i + 1 -lt $lines.Count -and $lines[$i+1] -match "^\s+String _formatearHora") {
            $endLine = $i
            break
        }
    }
}

Write-Host "Found method from line $startLine to $endLine"

if ($startLine -ge 0 -and $endLine -gt $startLine) {
    # Build new method content
    $newMethod = @(
        '  /// Sincroniza el registro de estacionamiento con el servidor en background.',
        '  /// Usa [_agregarEnProcesoSeguro] para proteger la operacion con timeout.',
        '  /// Si el servidor responde 409 (conflicto), revierte el estado local.',
        '  /// Si falla por red, agrega a la cola de reintentos.',
        '  Future<void> _sincronizarRegistroServidor({',
        '    required Estacionamiento estacionCapturado,',
        '    required Estacionamiento_Tarjeta nuevoRegistro,',
        '    required String placa,',
        '    required int tarjeta,',
        '    required int tiempoCapturado,',
        '  }) async {',
        '    _agregarEnProcesoSeguro(estacionCapturado.id);',
        '',
        '    try {',
        '      // PASO 1: Registrar en est_tarjeta (POST)',
        '      await tarjeta_svc.registarEstacionamientoTarjeta(',
        '        nuevoRegistro,',
        '        token: _token,',
        '      );',
        '',
        '      // PASO 2: Marcar estacion como ocupada (PATCH)',
        '      await estacion_svc.actualizarRegistro(',
        '        estacionId: estacionCapturado.id,',
        '        placa: placa,',
        '        estado: true,',
        '        token: _token,',
        '      );',
        '',
        '      // PASO 3: Actualizar tiempo de tarjeta (PATCH a /api/tarjeta/)',
        '      final totalConsumido = _minutosConsumidosTarjeta(tarjeta);',
        '      unawaited(',
        '        tarjeta_svc.actualizarTiempoTarjeta(',
        '          tarjeta,',
        '          totalConsumido,',
        '          token: _token,',
        '        ),',
        '      );',
        '',
        '      // Exito: remover de _enProceso y mostrar mensaje',
        '      _removerEnProcesoSeguro(estacionCapturado.id);',
        '      if (mounted) {',
        '        _showCustomSnackBar(',
        '          "Estacionamiento #${estacionCapturado.numero} registrado correctamente",',
        '        );',
        '      }',
        '    } on tarjeta_svc.ApiConflictException catch (_) {',
        '      // 409: la estacion ya fue ocupada por otro usuario',
        '      _removerEnProcesoSeguro(estacionCapturado.id);',
        '      await _revertirRegistroLocal(estacionCapturado.id);',
        '    } catch (e) {',
        '      // Error de red: mantener estado optimista y agregar a cola de reintentos',
        '      _removerEnProcesoSeguro(estacionCapturado.id);',
        '      _agregarAColaReintentos(',
        '        _RegistroPendiente(',
        '          estacion: estacionCapturado,',
        '          registro: nuevoRegistro,',
        '          placa: placa,',
        '          tarjeta: tarjeta,',
        '          tiempo: tiempoCapturado,',
        '        ),',
        '      );',
        '      if (mounted) {',
        '        _showCustomSnackBar(',
        '          "Registro guardado localmente. El servidor no respondio, se sincronizara automaticamente.",',
        '          isWarning: true,',
        '        );',
        '      }',
        '    }',
        '  }'
    )
    
    # Remove old lines and insert new
    $newLines = $lines[0..($startLine-1)] + $newMethod + $lines[($endLine+1)..($lines.Count-1)]
    Set-Content $path $newLines -Encoding UTF8
    Write-Host "Reemplazo completado. Nuevo tamano: $($newLines.Count) lineas"
} else {
    Write-Host "No se encontro el metodo"
}

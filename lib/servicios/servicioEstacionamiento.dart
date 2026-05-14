import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:estacionamientotarifado/tarjetas/models/Estacionamiento.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';

/// Error lanzado cuando el servidor responde con un código HTTP de error.
class ApiStatusException implements Exception {
  final int statusCode;
  final String body;

  ApiStatusException(this.statusCode, this.body);

  @override
  String toString() =>
      'ApiStatusException(statusCode: $statusCode, body: $body)';
}

/// Error específico para conflicto de concurrencia (HTTP 409).
/// Se lanza cuando otro usuario ya registró la misma estación.
class ApiConflictException implements Exception {
  final int estacionId;
  final String body;

  ApiConflictException(this.estacionId, this.body);

  @override
  String toString() =>
      'ApiConflictException(estacionId: $estacionId, body: $body)';
}

const String _urlEstacion =
    'https://simert.transitoelguabo.gob.ec/api/estacion/';

Uri _uriTkEstacion(String path, String token) {
  final url = '$_urlEstacion$path';
  return token.isEmpty
      ? Uri.parse(url)
      : Uri.parse('$url?_tk=${Uri.encodeComponent(token)}');
}

Future<List<Estacionamiento>> fetchEstacionamientos({String token = ''}) async {
  final response = await HttpMonitorizado.get(_uriTkEstacion('', token));

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(response.body);
    return jsonData.map((item) => Estacionamiento.fromJson(item)).toList();
  } else {
    throw Exception('Error al cargar las estaciones');
  }
}

/// Obtiene UNA estación específica por su ID.
/// Útil para verificar el estado actual antes de registrar.
Future<Estacionamiento?> fetchEstacionamientoPorId(
  int estacionId, {
  String token = '',
}) async {
  try {
    final response = await HttpMonitorizado.get(
      _uriTkEstacion('$estacionId/', token),
    ).timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      return Estacionamiento.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
  } catch (_) {
    // Silencioso: si falla, confiar en estado local
  }
  return null;
}

Future<void> actualizarRegistro({
  required int estacionId,
  required bool estado,
  required String placa,
  String token = '',
}) async {
  final url = _uriTkEstacion('$estacionId/', token);

  final body = json.encode({
    'id': estacionId,
    'placa': placa,
    'estado': estado,
  });

  try {
    debugPrint(
      '[ACTUALIZAR]  Enviando actualización a #$estacionId: estado=$estado, placa=$placa',
    );
    final response =
        await HttpMonitorizado.put(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('Timeout al actualizar estación'),
        );

    debugPrint(
      '[ACTUALIZAR]  Status: ${response.statusCode}, Body: ${response.body}',
    );

    if (response.statusCode == 200) {
      debugPrint('[OK]  Registro #$estacionId actualizado correctamente');
    } else if (response.statusCode == 409) {
      // Conflicto: otro usuario ya modificó este recurso
      debugPrint(
        '[CONFLICTO]  Estación #$estacionId ya fue registrada por otro usuario',
      );
      throw ApiConflictException(estacionId, response.body);
    } else {
      debugPrint(
        '[ERROR]  Error al actualizar #$estacionId: ${response.statusCode} ${response.body}',
      );
      throw ApiStatusException(response.statusCode, response.body);
    }
  } catch (e) {
    debugPrint('[ERROR]  Excepción en actualizarRegistro: $e');
    rethrow;
  }
}

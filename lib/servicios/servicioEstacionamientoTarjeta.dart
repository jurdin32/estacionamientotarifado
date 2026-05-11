import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:estacionamientotarifado/tarjetas/models/Tarjetas.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';

/// Error específico para conflicto de concurrencia (HTTP 409).
/// Se lanza cuando el servidor detecta que la estación ya está ocupada
/// por otro registro simultáneo.
class ApiConflictException implements Exception {
  final int estacionId;
  final String body;

  ApiConflictException(this.estacionId, this.body);

  @override
  String toString() =>
      'ApiConflictException(estacionId: $estacionId, body: $body)';
}

const String _urlEstTarjeta =
    'https://simert.transitoelguabo.gob.ec/api/est_tarjeta/';

Uri _uriTkTarjeta(String token) {
  return token.isEmpty
      ? Uri.parse(_urlEstTarjeta)
      : Uri.parse('$_urlEstTarjeta?_tk=${Uri.encodeComponent(token)}');
}

Future<List<Estacionamiento_Tarjeta>> fetchEstacionamientoTarjeta({
  String token = '',
}) async {
  final response = await HttpMonitorizado.get(_uriTkTarjeta(token));

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(response.body);
    return jsonData
        .map((item) => Estacionamiento_Tarjeta.fromJson(item))
        .toList();
  } else {
    throw Exception('Error al cargar las estaciones: ${response.statusCode}');
  }
}

const String _urlTarjeta = 'https://simert.transitoelguabo.gob.ec/api/tarjeta/';

Uri _uriTkTarjetaBase(String token) {
  return token.isEmpty
      ? Uri.parse(_urlTarjeta)
      : Uri.parse('$_urlTarjeta?_tk=${Uri.encodeComponent(token)}');
}

/// Descarga /api/tarjeta/ y devuelve {numero → minutos_consumidos}.
Future<Map<int, int>> fetchTarjetasTiempo({String token = ''}) async {
  final resp = await HttpMonitorizado.get(_uriTkTarjetaBase(token));
  if (resp.statusCode != 200) return {};
  final List<dynamic> items = json.decode(resp.body);
  return {
    for (final t in items.cast<Map<String, dynamic>>())
      (t['numero'] as num).toInt(): (t['tiempo'] as num?)?.toInt() ?? 0,
  };
}

/// Caché local de {numero → id} para evitar GET completo antes de cada PATCH.
Map<int, int> _tarjetaIdCache = {};

/// Busca la tarjeta con [numero] en /api/tarjeta/ y actualiza su `tiempo`
/// con el valor [totalMinutos] (ya calculado, máximo 120).
/// Usa caché local de IDs para evitar un GET completo en cada llamada.
Future<void> actualizarTiempoTarjeta(
  int numero,
  int totalMinutos, {
  String token = '',
}) async {
  final tiempoFinal = totalMinutos.clamp(0, 120);

  int? id = _tarjetaIdCache[numero];
  if (id == null) {
    final listResp = await HttpMonitorizado.get(_uriTkTarjetaBase(token));
    if (listResp.statusCode != 200) return;

    final List<dynamic> items = json.decode(listResp.body);
    // Llenar caché completo para evitar futuros GETs
    for (final t in items.cast<Map<String, dynamic>>()) {
      _tarjetaIdCache[(t['numero'] as num).toInt()] = (t['id'] as num).toInt();
    }
    id = _tarjetaIdCache[numero];
    if (id == null) return;
  }

  final patchUri = token.isEmpty
      ? Uri.parse('$_urlTarjeta$id/')
      : Uri.parse('$_urlTarjeta$id/?_tk=${Uri.encodeComponent(token)}');

  final resp = await HttpMonitorizado.patch(
    patchUri,
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'tiempo': tiempoFinal}),
  );
  // Si falla con 404, invalidar caché y reintentar
  if (resp.statusCode == 404) {
    _tarjetaIdCache.remove(numero);
  }
  debugPrint('⏱ Tarjeta #$numero → $tiempoFinal min');
}

Future<Estacionamiento_Tarjeta> registarEstacionamientoTarjeta(
  Estacionamiento_Tarjeta est, {
  String token = '',
}) async {
  final response = await HttpMonitorizado.post(
    _uriTkTarjeta(token),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(est.toJson()),
  );
  if (response.statusCode == 201 || response.statusCode == 200) {
    return Estacionamiento_Tarjeta.fromJson(json.decode(response.body));
  } else if (response.statusCode == 409) {
    // Conflicto: la estación ya está ocupada por otro registro simultáneo
    throw ApiConflictException(est.estacionId, response.body);
  } else {
    String mensajeError;
    try {
      final rawBody = response.body;
      debugPrint('❌ Error servidor (${response.statusCode}): $rawBody');
      final body = json.decode(rawBody);
      if (body is Map) {
        // Intentar extraer mensaje de error de diferentes formatos posibles
        if (body['non_field_errors'] != null) {
          final errors = body['non_field_errors'];
          mensajeError = errors is List ? errors.join(', ') : errors.toString();
        } else if (body['detail'] != null) {
          mensajeError = body['detail'].toString();
        } else if (body['placa'] != null) {
          final errors = body['placa'];
          mensajeError = errors is List ? errors.join(', ') : errors.toString();
        } else if (body['estacion'] != null) {
          final errors = body['estacion'];
          mensajeError = errors is List ? errors.join(', ') : errors.toString();
        } else if (body['usuario'] != null) {
          final errors = body['usuario'];
          mensajeError = errors is List ? errors.join(', ') : errors.toString();
        } else {
          // Tomar el primer valor de error disponible
          final primerError = body.values.firstWhere(
            (v) => v != null && v.toString().isNotEmpty,
            orElse: () => 'Error desconocido',
          );
          mensajeError = primerError is List
              ? primerError.join(', ')
              : primerError.toString();
        }
      } else {
        mensajeError = 'Error del servidor (${response.statusCode})';
      }
    } catch (_) {
      mensajeError = 'Error del servidor (${response.statusCode})';
    }
    throw Exception('Error al crear el estacionamiento: $mensajeError');
  }
}

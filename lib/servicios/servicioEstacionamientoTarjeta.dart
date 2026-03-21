import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:estacionamientotarifado/tarjetas/models/Tarjetas.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';

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
  } else {
    throw Exception(
      'Error al crear el estacionamiento: ${json.decode(response.body)['non_field_errors'][0]}',
    );
  }
}

import 'dart:convert';
import 'package:estacionamientotarifado/tarjetas/models/Estacionamiento.dart';
import 'package:http/http.dart' as http;

const String _urlEstacion =
    'https://simert.transitoelguabo.gob.ec/api/estacion/';

Uri _uriTkEstacion(String path, String token) {
  final url = '$_urlEstacion$path';
  return token.isEmpty
      ? Uri.parse(url)
      : Uri.parse('$url?_tk=${Uri.encodeComponent(token)}');
}

Future<List<Estacionamiento>> fetchEstacionamientos({String token = ''}) async {
  final response = await http.get(_uriTkEstacion('', token));

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(response.body);
    return jsonData.map((item) => Estacionamiento.fromJson(item)).toList();
  } else {
    throw Exception('Error al cargar las estaciones');
  }
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
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    print('Status: ${response.statusCode}');
    print('Respuesta API: ${response.body}');

    if (response.statusCode == 200) {
      print('Registro actualizado correctamente');
    } else {
      print(
        'Error al actualizar registro: ${response.statusCode} ${response.body}',
      );
      throw Exception('Error al actualizar registro');
    }
  } catch (e) {
    print('Error en la solicitud: $e');
    throw Exception('Error en la solicitud');
  }
}

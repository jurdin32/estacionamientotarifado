import 'dart:async';
import 'dart:convert';

import 'package:estacionamientotarifado/tarjetas/models/Multa.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final String urlapi2 =
    'https://simert.transitoelguabo.gob.ec/api/details_multas';

Future<List<Multa>> fetchMultas() async {
  final response = await http
      .get(Uri.parse(urlapi2))
      .timeout(const Duration(seconds: 30));

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(response.body);
    return jsonData.map((item) => Multa.fromJson(item)).toList();
  } else {
    throw Exception('Error al cargar las multas: ${response.statusCode}');
  }
}

Future<void> guardarMultasEnPreferencias(List<Multa> multas) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String multasString = json.encode(multas.map((m) => m.toJson()).toList());
  await prefs.setString('multas', multasString);
}

Future<List<Multa>> obtenerMultasGuardadas() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? multasString = prefs.getString('multas');
  if (multasString != null) {
    List<dynamic> jsonData = json.decode(multasString);
    return jsonData.map((item) => Multa.fromJson(item)).toList();
  }
  return [];
}

// servicios/notificacion_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:estacionamientotarifado/tarjetas/models/Notificacion.dart';
import 'package:estacionamientotarifado/tarjetas/models/Multa.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class NotificacionService {
  static const String _baseUrl =
      'https://simert.transitoelguabo.gob.ec/api/notificaciondetalle/';
  static const String _evidenciaUrl =
      'https://simert.transitoelguabo.gob.ec/api/evidencia/';

  // Método para registrar la notificación
  static Future<Map<String, dynamic>> registrarNotificacion(
    DetalleNotificacion detalle,
  ) async {
    try {
      // Obtener credenciales para autenticación
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      // Construir URL con token (Apache elimina header Authorization)
      final uri = token.isNotEmpty
          ? Uri.parse('$_baseUrl?_tk=${Uri.encodeComponent(token)}')
          : Uri.parse(_baseUrl);

      final Map<String, dynamic> requestBody = detalle.toJson();

      print("📤 Enviando datos a la API...");
      print("📊 JSON enviado: ${json.encode(requestBody)}");

      final response = await HttpMonitorizado.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print("📥 Respuesta recibida:");
      print("🔹 Status Code: ${response.statusCode}");
      print("🔹 Body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        return {
          'exito': true,
          'mensaje': 'Notificación registrada exitosamente',
          'data': responseData,
          'statusCode': response.statusCode,
          'idNotificacion':
              responseData['id'] ?? _extraerIdDeResponse(responseData),
        };
      } else {
        String errorMessage = 'Error del servidor';
        try {
          final errorData = json.decode(response.body);
          // DRF devuelve errores como {"campo": ["error"]} o {"detail": "..."}
          if (errorData is Map) {
            if (errorData.containsKey('detail')) {
              errorMessage = errorData['detail'].toString();
            } else if (errorData.containsKey('message')) {
              errorMessage = errorData['message'].toString();
            } else if (errorData.containsKey('error')) {
              errorMessage = errorData['error'].toString();
            } else {
              // Parsear errores de validación por campo
              final errores = <String>[];
              errorData.forEach((key, value) {
                if (value is List) {
                  errores.add('$key: ${value.join(', ')}');
                } else {
                  errores.add('$key: $value');
                }
              });
              if (errores.isNotEmpty) {
                errorMessage = errores.join('\n');
              }
            }
          }
        } catch (e) {
          errorMessage = 'Error ${response.statusCode}: ${response.body}';
        }

        return {
          'exito': false,
          'mensaje': errorMessage,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print("❌ Error en la solicitud: $e");
      return {
        'exito': false,
        'mensaje': 'Error de conexión: $e',
        'statusCode': 0,
      };
    }
  }

  // Método para extraer ID de la respuesta
  static int? _extraerIdDeResponse(Map<String, dynamic> responseData) {
    try {
      if (responseData.containsKey('notificacion') &&
          responseData['notificacion'] is Map) {
        return responseData['notificacion']['id'] as int?;
      }
      return responseData['id'] as int?;
    } catch (e) {
      return null;
    }
  }

  // Método para subir evidencias fotográficas
  static Future<Map<String, dynamic>> subirEvidencias(
    int idNotificacion,
    List<File> imagenes,
  ) async {
    try {
      // Obtener credenciales para autenticación
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final sessionCookie = prefs.getString('session_cookie') ?? '';

      // Construir URL con token (Apache elimina header Authorization)
      final uri = token.isNotEmpty
          ? Uri.parse(_evidenciaUrl).replace(queryParameters: {'_tk': token})
          : Uri.parse(_evidenciaUrl);

      List<Map<String, dynamic>> resultados = [];

      for (int i = 0; i < imagenes.length; i++) {
        final File imagen = imagenes[i];

        // Verificar que el archivo existe
        if (!await imagen.exists()) {
          resultados.add({
            'indice': i,
            'exito': false,
            'mensaje': 'El archivo no existe',
          });
          continue;
        }

        // Crear la solicitud multipart
        var request = http.MultipartRequest('POST', uri);

        // Headers de autenticación
        if (token.isNotEmpty) {
          request.headers['Authorization'] = 'Token $token';
        }
        if (sessionCookie.isNotEmpty) {
          request.headers['Cookie'] = sessionCookie;
        }
        request.headers['Accept'] = 'application/json';

        // Agregar campos
        request.fields['dNotificaicon'] = idNotificacion.toString();

        // Agregar archivo
        String extension = imagen.path.split('.').last.toLowerCase();
        String mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';

        request.files.add(
          await http.MultipartFile.fromPath(
            'evidencia',
            imagen.path,
            contentType: MediaType.parse(mimeType),
          ),
        );

        print(
          "📤 Subiendo evidencia ${i + 1} para notificación $idNotificacion",
        );
        print("🔹 Archivo: ${imagen.path}");
        print("🔹 Tipo MIME: $mimeType");

        // Enviar solicitud
        final response = await request.send();
        final responseBody = await response.stream.bytesToString();

        print("📥 Respuesta evidencia ${i + 1}:");
        print("🔹 Status Code: ${response.statusCode}");
        print("🔹 Body: $responseBody");

        if (response.statusCode == 200 || response.statusCode == 201) {
          resultados.add({
            'indice': i,
            'exito': true,
            'mensaje': 'Evidencia subida exitosamente',
            'statusCode': response.statusCode,
          });
        } else {
          resultados.add({
            'indice': i,
            'exito': false,
            'mensaje': 'Error ${response.statusCode}: $responseBody',
            'statusCode': response.statusCode,
          });
        }
      }

      // Verificar si todas las evidencias se subieron correctamente
      bool todasExitosas = resultados.every(
        (result) => result['exito'] == true,
      );
      int exitosas = resultados
          .where((result) => result['exito'] == true)
          .length;

      return {
        'exito': todasExitosas,
        'mensaje': 'Se subieron $exitosas de ${imagenes.length} evidencias',
        'resultados': resultados,
        'totalEnviadas': imagenes.length,
        'totalExitosas': exitosas,
      };
    } catch (e) {
      print("❌ Error subiendo evidencias: $e");
      return {
        'exito': false,
        'mensaje': 'Error subiendo evidencias: $e',
        'resultados': [],
        'totalEnviadas': imagenes.length,
        'totalExitosas': 0,
      };
    }
  }

  // Método para seleccionar imágenes desde la galería
  static Future<List<File>> seleccionarImagenes(
    ImagePicker picker,
    int maxImagenes,
  ) async {
    try {
      final List<XFile> xFiles = await picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (xFiles.isEmpty) {
        return [];
      }

      // Limitar al número máximo de imágenes
      final List<XFile> seleccionadas = xFiles.length > maxImagenes
          ? xFiles.sublist(0, maxImagenes)
          : xFiles;

      return seleccionadas.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      print("❌ Error seleccionando imágenes: $e");
      return [];
    }
  }

  // Método para tomar foto con la cámara
  static Future<File?> tomarFoto(ImagePicker picker) async {
    try {
      final XFile? foto = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (foto != null) {
        return File(foto.path);
      }
      return null;
    } catch (e) {
      print("❌ Error tomando foto: $e");
      return null;
    }
  }

  // Método para cargar datos del usuario
  static Future<Map<String, dynamic>> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'username': prefs.getString('username') ?? '',
        'name': prefs.getString('name') ?? '',
        'email': prefs.getString('email') ?? '',
        'id': prefs.getInt('id') ?? 0,
      };
    } catch (e) {
      return {'username': '', 'name': '', 'email': '', 'id': 0};
    }
  }

  // Método para formatear fecha y hora
  static String formatearFechaHora(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // Método para convertir fecha a formato ISO
  static String convertirFechaAISO(String fechaTexto) {
    try {
      final parts = fechaTexto.split(' ');
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');

      final fecha = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );

      return '${fecha.toIso8601String().substring(0, 19)}.000';
    } catch (e) {
      final ahora = DateTime.now();
      return '${ahora.toIso8601String().substring(0, 19)}.000';
    }
  }

  // Método para parsear fecha y hora
  static DateTime parsearFechaHora(String texto) {
    try {
      final parts = texto.split(' ');
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (e) {
      return DateTime.now();
    }
  }

  // Método para validar placa en tiempo real
  static Map<String, dynamic> validarPlacaEnTiempoReal(String text) {
    final placaRegex = RegExp(r'^([A-Z]{3}\d{4}|[A-Z]{2}\d{3}[A-Z])$');

    if (text.isEmpty) {
      return {'valida': false, 'mensajeError': '', 'textoConvertido': text};
    }

    // Convertir a mayúsculas
    final textoMayusculas = text.toUpperCase();
    if (text != textoMayusculas) {
      return {
        'valida': false,
        'mensajeError': '',
        'textoConvertido': textoMayusculas,
      };
    }

    if (!RegExp(r'^[A-Z0-9]*$').hasMatch(textoMayusculas)) {
      return {
        'valida': false,
        'mensajeError': 'Solo letras y números permitidos',
        'textoConvertido': textoMayusculas,
      };
    }

    if (textoMayusculas.length > 7) {
      return {
        'valida': false,
        'mensajeError': 'Máximo 7 caracteres',
        'textoConvertido': textoMayusculas.substring(0, 7),
      };
    }

    if (textoMayusculas.length == 6 || textoMayusculas.length == 7) {
      final bool esValida = placaRegex.hasMatch(textoMayusculas);
      return {
        'valida': esValida,
        'mensajeError': esValida
            ? ''
            : 'Formato inválido. Solo ABC1234 o AB123C',
        'textoConvertido': textoMayusculas,
      };
    } else {
      return {
        'valida': false,
        'mensajeError': '',
        'textoConvertido': textoMayusculas,
      };
    }
  }

  // Método para crear objeto Notificacion
  static Notificacion crearNotificacion({
    required String fechaEmision,
    required String ubicacion,
    required String placa,
    required String observacion,
    required String numeroComprobante,
    required int usuarioId,
  }) {
    return Notificacion(
      id: 0,
      numero: "",
      fecha_emision: convertirFechaAISO(fechaEmision),
      ubicacion: ubicacion,
      placa: placa,
      cedula: "",
      nombres: "",
      apellidos: "",
      telefono: "",
      direccion: "",
      email: "",
      estado: false,
      anulado: false,
      observacion: observacion,
      numero_comprobante: numeroComprobante.isNotEmpty
          ? numeroComprobante
          : DateTime.now().millisecondsSinceEpoch.toString(),
      eliminado: false,
      impugnacion: false,
      fecha_resolucion: null,
      impugnacion_favorable: false,
      impugnacion_no_favorable: false,
      observacion_impugnacion: "",
      resolucion: null,
      numero_resolucion: "",
      usuario: usuarioId,
    );
  }

  // Método para crear objeto DetalleNotificacion
  static DetalleNotificacion crearDetalleNotificacion({
    required Notificacion notificacion,
    required Multa? multaSeleccionada,
  }) {
    return DetalleNotificacion(
      notificacion: notificacion,
      fecha: DateTime.now(),
      total: multaSeleccionada?.valor ?? 0.0,
      estado: true,
      procede: true,
      multa: multaSeleccionada?.id ?? 0,
    );
  }
}

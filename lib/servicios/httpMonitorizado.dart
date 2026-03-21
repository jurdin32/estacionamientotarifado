import 'dart:convert';
import 'package:http/http.dart' as http;
import 'monitorDatos.dart';

/// Cliente HTTP que registra automáticamente el consumo de datos.
///
/// Usar en lugar de `http.get(...)`, `http.post(...)`, etc.
/// ```dart
/// final resp = await HttpMonitorizado.get(uri, headers: headers);
/// ```
class HttpMonitorizado {
  static final MonitorDatos _monitor = MonitorDatos.instancia;

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final bytesReq = _estimarBytesRequest('GET', url, headers, null);
    final resp = await http.get(url, headers: headers);
    _monitor.registrarRequest(
      bytesReq,
      resp.contentLength ?? resp.bodyBytes.length,
      _extraerEndpoint(url),
      metodo: 'GET',
      statusCode: resp.statusCode,
    );
    return resp;
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final bytesReq = _estimarBytesRequest('POST', url, headers, body);
    final resp = await http.post(
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    );
    _monitor.registrarRequest(
      bytesReq,
      resp.contentLength ?? resp.bodyBytes.length,
      _extraerEndpoint(url),
      metodo: 'POST',
      statusCode: resp.statusCode,
    );
    return resp;
  }

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final bytesReq = _estimarBytesRequest('PUT', url, headers, body);
    final resp = await http.put(
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    );
    _monitor.registrarRequest(
      bytesReq,
      resp.contentLength ?? resp.bodyBytes.length,
      _extraerEndpoint(url),
      metodo: 'PUT',
      statusCode: resp.statusCode,
    );
    return resp;
  }

  static Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final bytesReq = _estimarBytesRequest('PATCH', url, headers, body);
    final resp = await http.patch(
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    );
    _monitor.registrarRequest(
      bytesReq,
      resp.contentLength ?? resp.bodyBytes.length,
      _extraerEndpoint(url),
      metodo: 'PATCH',
      statusCode: resp.statusCode,
    );
    return resp;
  }

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final bytesReq = _estimarBytesRequest('DELETE', url, headers, body);
    final resp = await http.delete(
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    );
    _monitor.registrarRequest(
      bytesReq,
      resp.contentLength ?? resp.bodyBytes.length,
      _extraerEndpoint(url),
      metodo: 'DELETE',
      statusCode: resp.statusCode,
    );
    return resp;
  }

  // ── Utilidades ────────────────────────────────────────────────────────────

  static int _estimarBytesRequest(
    String method,
    Uri url,
    Map<String, String>? headers,
    Object? body,
  ) {
    int bytes = '$method ${url.path} HTTP/1.1\r\n'.length;
    bytes += 'Host: ${url.host}\r\n'.length;
    if (headers != null) {
      for (final entry in headers.entries) {
        bytes += '${entry.key}: ${entry.value}\r\n'.length;
      }
    }
    if (body != null) {
      if (body is String) {
        bytes += utf8.encode(body).length;
      } else if (body is List<int>) {
        bytes += body.length;
      } else if (body is Map) {
        bytes += utf8.encode(json.encode(body)).length;
      }
    }
    return bytes;
  }

  static String _extraerEndpoint(Uri url) {
    // Extraer solo el path sin query params ni host
    final path = url.path;
    if (path.length <= 50) return path;
    return '${path.substring(0, 47)}...';
  }
}

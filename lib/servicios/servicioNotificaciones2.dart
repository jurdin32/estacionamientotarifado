import 'dart:async';
import 'dart:convert';
import 'package:estacionamientotarifado/tarjetas/models/Multa.dart';
import 'package:estacionamientotarifado/tarjetas/models/Notificaciones2.dart';
import 'package:estacionamientotarifado/servicios/httpMonitorizado.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════════════════════
// CACHÉ LOCAL DE DETALLES DE NOTIFICACIONES
// Clave en SharedPreferences: 'detalles_mes_YYYY_MM'
// Válida durante todo el mes; al cambiar de mes se reemplaza automáticamente.
// ══════════════════════════════════════════════════════════════════════════════
class CacheDetallesService {
  static String _claveActual([String scope = '']) {
    final now = DateTime.now();
    final suffix = scope.isEmpty ? '' : '_$scope';
    return 'detalles_mes_${now.year}_${now.month.toString().padLeft(2, '0')}$suffix';
  }

  /// Retorna true si ya existe caché para el mes actual.
  static Future<bool> tieneCacheMesActual({String scope = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_claveActual(scope));
  }

  /// Lee todos los items del mes actual desde SharedPreferences.
  static Future<List<Map<String, dynamic>>> leerMes({String scope = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_claveActual(scope));
    if (raw == null) return [];
    try {
      final List<dynamic> list = json.decode(raw);
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Filtra la lista dada retornando solo los del día de hoy (sin llamar a prefs).
  static List<Map<String, dynamic>> leerHoy(List<Map<String, dynamic>> items) {
    final today = DateTime.now();
    return items.where((item) {
      try {
        final dt = DateTime.parse(item['fechaEmision'] as String);
        return dt.year == today.year &&
            dt.month == today.month &&
            dt.day == today.day;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  /// Persiste la lista completa del mes y elimina el caché del mes anterior.
  static Future<void> guardarMes(
    List<Map<String, dynamic>> items, {
    String scope = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveActual(scope), json.encode(items));
    // Limpiar mes anterior
    final now = DateTime.now();
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final suffix = scope.isEmpty ? '' : '_$scope';
    final prevKey =
        'detalles_mes_${prevYear}_${prevMonth.toString().padLeft(2, '0')}$suffix';
    await prefs.remove(prevKey);
  }

  /// Inserta o actualiza un item en el caché del mes (clave de dedup: idNotificacion).
  static Future<void> agregarItem(
    Map<String, dynamic> item, {
    String scope = '',
  }) async {
    final items = await leerMes(scope: scope);
    final idNotif = item['idNotificacion'] as int;
    items.removeWhere((e) => (e['idNotificacion'] as int?) == idNotif);
    items.insert(0, item);
    await guardarMes(items, scope: scope);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CACHÉ MENSUAL DE NOTIFICACIONES DEL USUARIO
// Clave: 'notif_mes_<userId>_YYYY_MM'
// ══════════════════════════════════════════════════════════════════════════════
class NotifMesCache {
  static String _clave(int userId) {
    final now = DateTime.now();
    return 'notif_mes_${userId}_${now.year}_${now.month.toString().padLeft(2, '0')}';
  }

  /// Lee el caché del mes actual. Retorna null si no existe.
  static Future<List<Notificacion>?> leer(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clave(userId));
    if (raw == null) return null;
    try {
      final List<dynamic> list = json.decode(raw);
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => Notificacion.fromJson(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Guarda la lista en caché y limpia el mes anterior.
  static Future<void> guardar(int userId, List<Notificacion> lista) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _clave(userId),
      json.encode(lista.map((n) => n.toJson()).toList()),
    );
    // Limpiar mes anterior
    final now = DateTime.now();
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevKey =
        'notif_mes_${userId}_${prevYear}_${prevMonth.toString().padLeft(2, '0')}';
    await prefs.remove(prevKey);
  }

  /// Retorna true si el servidor tiene datos distintos a los del caché
  /// (cantidad, IDs o estados difieren).
  static bool tieneDiferencias(
    List<Notificacion> local,
    List<Notificacion> server,
  ) {
    if (local.length != server.length) return true;
    final localMap = {for (final n in local) n.id: n.estado};
    for (final n in server) {
      if (!localMap.containsKey(n.id) || localMap[n.id] != n.estado) {
        return true;
      }
    }
    return false;
  }
}

// ══════════════════════════════════════════════════════════════════════════════

class NotificacionService {
  static const String baseUrl = 'https://simert.transitoelguabo.gob.ec/api';

  String _limpiarTexto(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    return s;
  }

  String _primeroNoVacio(Iterable<dynamic> candidatos) {
    for (final c in candidatos) {
      final v = _limpiarTexto(c);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  int _extraerUsuarioEmisorId(Map<String, dynamic> notifRaw) {
    final usuarioRaw = notifRaw['usuario'];
    if (usuarioRaw is int) return usuarioRaw;
    if (usuarioRaw is Map<String, dynamic>) {
      final id = usuarioRaw['id'];
      if (id is int) return id;
      return int.tryParse((id ?? '').toString()) ?? 0;
    }
    return int.tryParse((notifRaw['usuario_id'] ?? '').toString()) ?? 0;
  }

  String _extraerUsuarioEmisor(Map<String, dynamic> notifRaw) {
    final usuarioRaw = notifRaw['usuario'];
    if (usuarioRaw is Map<String, dynamic>) {
      final first = _limpiarTexto(usuarioRaw['first_name']);
      final last = _limpiarTexto(usuarioRaw['last_name']);
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full;

      final username = _limpiarTexto(usuarioRaw['username']);
      if (username.isNotEmpty) return username;

      final name = _limpiarTexto(usuarioRaw['name']);
      if (name.isNotEmpty) return name;
    }

    final directos = <dynamic>[
      notifRaw['usuario_nombre'],
      notifRaw['usuario_name'],
      notifRaw['usuario_username'],
      notifRaw['username'],
      notifRaw['name'],
    ];

    for (final c in directos) {
      final v = _limpiarTexto(c);
      if (v.isNotEmpty) return v;
    }

    return '';
  }

  Future<List<Notificacion>> _obtenerNotificaciones({
    required bool soloUsuarioActual,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('id') ?? 0;

      if (userId == 0) {
        throw Exception('No se encontró el ID del usuario en las preferencias');
      }

      final response = await HttpMonitorizado.get(
        Uri.parse('$baseUrl/notificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
      }

      final List<dynamic> jsonResponse = json.decode(response.body);
      final List<Notificacion> notificaciones = [];

      for (final item in jsonResponse) {
        try {
          if (item is! Map<String, dynamic>) continue;
          final notificacion = Notificacion.fromJson(item);
          if (!soloUsuarioActual || notificacion.usuario == userId) {
            notificaciones.add(notificacion);
          }
        } catch (_) {
          continue;
        }
      }

      return notificaciones;
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  Future<List<Notificacion>> getNotificaciones({
    String? notificacionId,
    String? cedula,
    String? placa,
    String? username,
    String? fechaInicio,
    String? fechaFin,
    bool soloUsuarioActual = true,
  }) async {
    return _obtenerNotificaciones(soloUsuarioActual: soloUsuarioActual);
  }

  List<Notificacion> filtrarNotificacionesMesActual(
    List<Notificacion> notificaciones,
  ) {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    print('📅 Filtrando por mes: $currentMonth, año: $currentYear');

    final notificacionesFiltradas = notificaciones.where((notificacion) {
      try {
        // Excluir anulados y eliminados
        if (notificacion.anulado || notificacion.eliminado) {
          return false;
        }

        // Verificar que fechaEmision no sea nula o vacía
        if (notificacion.fechaEmision == 'N/A' ||
            notificacion.fechaEmision.isEmpty ||
            notificacion.fechaEmision == 'null') {
          return false;
        }

        // Convertir la fecha string a DateTime para comparación segura
        final fecha = DateTime.parse(notificacion.fechaEmision);
        return fecha.year == currentYear && fecha.month == currentMonth;
      } catch (e) {
        print('❌ Error procesando fecha: ${notificacion.fechaEmision} - $e');
        return false;
      }
    }).toList();

    print('🎯 Notificaciones filtradas: ${notificacionesFiltradas.length}');
    return notificacionesFiltradas;
  }

  // Método para obtener TODAS las notificaciones del usuario (sin filtrar por mes)
  Future<List<Notificacion>> getTodasNotificacionesUsuario() async {
    return _obtenerNotificaciones(soloUsuarioActual: true);
  }

  Future<List<Notificacion>> getTodasNotificacionesSistema() async {
    return _obtenerNotificaciones(soloUsuarioActual: false);
  }

  Future<Map<String, dynamic>?> getDetallePorNotificacion(
    int notificacionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('token') ?? '').trim();

    final query = <String, String>{
      'notificacion__id': '$notificacionId',
      'notificacion__cedula': '',
      'notificacion__placa': '',
      'notificacion__usuario__username': '',
      'fecha_inicio': '',
      'fecha_fin': '',
      if (token.isNotEmpty) '_tk': token,
    };

    final uri = Uri.parse(
      '$baseUrl/notificaciondetalle/',
    ).replace(queryParameters: query);

    final response = await HttpMonitorizado.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Token $token',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo consultar detalle de multa (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final notif = item['notificacion'];
      if (notif is Map<String, dynamic> &&
          (notif['id'] as int?) == notificacionId) {
        return item;
      }
    }

    final first = decoded.first;
    return first is Map<String, dynamic> ? first : null;
  }

  Future<void> actualizarCaracteristicasMulta({
    required int detalleId,
    required int multaId,
    required double total,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('token') ?? '').trim();

    final uri = token.isNotEmpty
        ? Uri.parse(
            '$baseUrl/notificaciondetalle/$detalleId/',
          ).replace(queryParameters: {'_tk': token})
        : Uri.parse('$baseUrl/notificaciondetalle/$detalleId/');

    final payload = json.encode({
      'multa': multaId,
      'total': double.parse(total.toStringAsFixed(2)),
    });

    final response = await HttpMonitorizado.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Token $token',
      },
      body: payload,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200 || response.statusCode == 202) {
      return;
    }

    throw Exception(
      'No se pudo actualizar la multa (${response.statusCode}): ${response.body}',
    );
  }

  // Método para agrupar notificaciones por estado
  Map<String, List<Notificacion>> agruparPorEstado(
    List<Notificacion> notificaciones,
  ) {
    final pagadas = <Notificacion>[];
    final impagas = <Notificacion>[];
    final impugnadas = <Notificacion>[];

    for (final notificacion in notificaciones) {
      if (notificacion.impugnacion) {
        impugnadas.add(notificacion);
      } else if (notificacion.estado) {
        // estado = true → pagado
        pagadas.add(notificacion);
      } else {
        // estado = false → impago
        impagas.add(notificacion);
      }
    }

    print(
      '📊 Agrupación - Pagadas: ${pagadas.length}, Impagas: ${impagas.length}, Impugnadas: ${impugnadas.length}',
    );

    return {'pagadas': pagadas, 'impagas': impagas, 'impugnadas': impugnadas};
  }

  /// Obtiene los detalles de notificaciones del día actual.
  /// - Si [verTodasUsuarios] es true, no filtra por usuario (modo administrador).
  /// - Si [verTodasUsuarios] es false, retorna solo del usuario autenticado.
  /// - Si existe caché del mes actual y [forceRefresh] es false, retorna desde caché.
  /// - Si no existe caché o [forceRefresh] es true, consulta la API, guarda en caché
  ///   y retorna solo los registros del día de hoy.
  Future<List<Map<String, dynamic>>> getDetallesHoy(
    int userId,
    List<Multa> multasCache, {
    bool forceRefresh = false,
    bool verTodasUsuarios = false,
  }) async {
    final cacheScope = verTodasUsuarios
        ? 'reimpresion_all'
        : 'reimpresion_user_$userId';

    if (!forceRefresh &&
        await CacheDetallesService.tieneCacheMesActual(scope: cacheScope)) {
      return await CacheDetallesService.leerMes(scope: cacheScope);
    }

    // ── Consultar API con endpoint correcto ──────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';

    final now = DateTime.now();
    final inicio = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final ultimoDia = DateTime(now.year, now.month + 1, 0).day;
    final fin =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${ultimoDia.toString().padLeft(2, '0')}';

    final query = <String, String>{
      'notificacion__id': '',
      'notificacion__cedula': '',
      'notificacion__placa': '',
      'fecha_inicio': inicio,
      'fecha_fin': fin,
      if (!verTodasUsuarios) 'notificacion__usuario__username': username,
    };
    final uri = Uri.parse(
      '$baseUrl/notificaciondetalle/',
    ).replace(queryParameters: query);

    final response = await HttpMonitorizado.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Error HTTP ${response.statusCode}');
    }

    final List<dynamic> jsonList = json.decode(response.body);
    final result = <Map<String, dynamic>>[];

    for (final item in jsonList) {
      try {
        final notifRaw = item['notificacion'];
        if (notifRaw is! Map<String, dynamic>) continue;
        final vehiculoRaw = notifRaw['vehiculo'];
        final vehiculo = vehiculoRaw is Map<String, dynamic>
            ? vehiculoRaw
            : const <String, dynamic>{};

        final bool anulado = notifRaw['anulado'] as bool? ?? false;
        final bool eliminado = notifRaw['eliminado'] as bool? ?? false;
        if (anulado || eliminado) continue;

        final String fechaStr = notifRaw['fecha_emision'] as String? ?? '';
        if (fechaStr.isEmpty || fechaStr == 'null') continue;

        final int multaId = item['multa'] as int? ?? 0;
        final double total =
            double.tryParse(item['total']?.toString() ?? '') ?? 0.0;

        String tipoMulta = 'Infracción #$multaId';
        double valorMulta = total;
        try {
          final m = multasCache.firstWhere((m) => m.id == multaId);
          tipoMulta = m.detalleMulta;
          if (valorMulta == 0.0) valorMulta = m.valor;
        } catch (_) {}

        final nombres = _primeroNoVacio([
          notifRaw['nombres'],
          notifRaw['nombre'],
          notifRaw['propietario'],
          notifRaw['conductor_nombre'],
          notifRaw['infractor_nombre'],
        ]);
        final apellidos = _primeroNoVacio([
          notifRaw['apellidos'],
          notifRaw['apellido'],
          notifRaw['conductor_apellido'],
          notifRaw['infractor_apellido'],
        ]);
        final nombrePersona = '$nombres $apellidos'.trim().isNotEmpty
            ? '$nombres $apellidos'.trim()
            : _primeroNoVacio([
                notifRaw['conductor'],
                notifRaw['infractor'],
                notifRaw['razon_social'],
              ]);

        final cedula = _primeroNoVacio([
          notifRaw['cedula'],
          notifRaw['identificacion'],
          notifRaw['dni'],
          notifRaw['documento'],
        ]);
        final marca = _primeroNoVacio([
          notifRaw['marca'],
          notifRaw['marca_vehiculo'],
          notifRaw['vehiculo_marca'],
          vehiculo['marca'],
        ]);
        final modelo = _primeroNoVacio([
          notifRaw['modelo'],
          notifRaw['modelo_vehiculo'],
          notifRaw['vehiculo_modelo'],
          vehiculo['modelo'],
        ]);
        final color = _primeroNoVacio([
          notifRaw['color'],
          notifRaw['color_vehiculo'],
          notifRaw['vehiculo_color'],
          vehiculo['color'],
        ]);
        final tipoVehiculo = _primeroNoVacio([
          notifRaw['tipo_vehiculo'],
          notifRaw['tipoVehiculo'],
          notifRaw['clase_vehiculo'],
          notifRaw['claseVehiculo'],
          vehiculo['tipo_vehiculo'],
          vehiculo['tipoVehiculo'],
          vehiculo['clase_vehiculo'],
          vehiculo['claseVehiculo'],
        ]);

        result.add({
          'idDetalle': item['id'] ?? 0,
          'idNotificacion': notifRaw['id'] ?? 0,
          'usuarioId': _extraerUsuarioEmisorId(notifRaw),
          'usuarioEmisor': _extraerUsuarioEmisor(notifRaw),
          'nombrePersona': nombrePersona,
          'cedula': cedula,
          'placa': (notifRaw['placa'] as String? ?? '').toUpperCase(),
          'marca': marca,
          'modelo': modelo,
          'color': color,
          'tipoVehiculo': tipoVehiculo,
          'tipoMulta': tipoMulta,
          'valor': valorMulta,
          'fechaEmision': fechaStr,
          'ubicacion': notifRaw['ubicacion'] as String? ?? '',
          'comprobante': notifRaw['numero_comprobante']?.toString() ?? '',
          'observacion': notifRaw['observacion'] as String? ?? '',
          'anulado': anulado,
        });
      } catch (_) {
        continue;
      }
    }

    result.sort((a, b) {
      try {
        return DateTime.parse(
          b['fechaEmision'] as String,
        ).compareTo(DateTime.parse(a['fechaEmision'] as String));
      } catch (_) {
        return 0;
      }
    });

    // Guardar todo el mes en caché
    await CacheDetallesService.guardarMes(result, scope: cacheScope);

    // Retornar todos los registros del mes
    return result;
  }
}

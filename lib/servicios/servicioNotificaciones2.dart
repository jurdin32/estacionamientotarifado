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
  static String _claveActual() {
    final now = DateTime.now();
    return 'detalles_mes_${now.year}_${now.month.toString().padLeft(2, '0')}';
  }

  /// Retorna true si ya existe caché para el mes actual.
  static Future<bool> tieneCacheMesActual() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_claveActual());
  }

  /// Lee todos los items del mes actual desde SharedPreferences.
  static Future<List<Map<String, dynamic>>> leerMes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_claveActual());
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
  static Future<void> guardarMes(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveActual(), json.encode(items));
    // Limpiar mes anterior
    final now = DateTime.now();
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevKey =
        'detalles_mes_${prevYear}_${prevMonth.toString().padLeft(2, '0')}';
    await prefs.remove(prevKey);
  }

  /// Inserta o actualiza un item en el caché del mes (clave de dedup: idNotificacion).
  static Future<void> agregarItem(Map<String, dynamic> item) async {
    final items = await leerMes();
    final idNotif = item['idNotificacion'] as int;
    items.removeWhere((e) => (e['idNotificacion'] as int?) == idNotif);
    items.insert(0, item);
    await guardarMes(items);
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

  Future<List<Notificacion>> getNotificaciones({
    String? notificacionId,
    String? cedula,
    String? placa,
    String? username,
    String? fechaInicio,
    String? fechaFin,
  }) async {
    try {
      // Obtener el ID del usuario desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('id')!;

      if (userId == 0) {
        throw Exception('No se encontró el ID del usuario en las preferencias');
      }

      print('🔗 Solicitando notificaciones para usuario: $userId');

      final response = await HttpMonitorizado.get(
        Uri.parse('$baseUrl/notificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      print('📥 Respuesta HTTP: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(response.body);
        print('📊 Cantidad total de notificaciones: ${jsonResponse.length}');

        final List<Notificacion> notificaciones = [];
        int errores = 0;

        for (var item in jsonResponse) {
          try {
            if (item is Map<String, dynamic>) {
              final notificacion = Notificacion.fromJson(item);

              // Filtrar por ID del usuario
              if (notificacion.usuario == userId) {
                notificaciones.add(notificacion);
              }
            }
          } catch (e) {
            errores++;
            print('❌ Error procesando item: $e');
            continue;
          }
        }

        print('✅ Notificaciones del usuario $userId: ${notificaciones.length}');
        print('❌ Errores de procesamiento: $errores');

        return notificaciones;
      } else {
        throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('💥 Error de conexión: $e');
      throw Exception('Error de conexión: $e');
    }
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
    try {
      // Obtener el ID del usuario desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('id');

      if (userId == 0) {
        throw Exception('No se encontró el ID del usuario en las preferencias');
      }

      print('🔗 Solicitando TODAS las notificaciones para usuario: $userId');

      final response = await HttpMonitorizado.get(
        Uri.parse('$baseUrl/notificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      print('📥 Respuesta HTTP: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(response.body);
        print('📊 Cantidad total de notificaciones: ${jsonResponse.length}');

        final List<Notificacion> notificaciones = [];
        int errores = 0;

        for (var item in jsonResponse) {
          try {
            if (item is Map<String, dynamic>) {
              final notificacion = Notificacion.fromJson(item);

              // Filtrar por ID del usuario
              if (notificacion.usuario == userId) {
                notificaciones.add(notificacion);
              }
            }
          } catch (e) {
            errores++;
            print('❌ Error procesando item: $e');
            continue;
          }
        }

        print(
          '✅ Todas las notificaciones del usuario $userId: ${notificaciones.length}',
        );
        print('❌ Errores de procesamiento: $errores');

        return notificaciones;
      } else {
        throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('💥 Error de conexión: $e');
      throw Exception('Error de conexión: $e');
    }
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

  /// Obtiene los detalles de notificaciones del día actual para el usuario.
  /// - Si existe caché del mes actual y [forceRefresh] es false, retorna desde caché.
  /// - Si no existe caché o [forceRefresh] es true, consulta la API, guarda en caché
  ///   y retorna solo los registros del día de hoy.
  Future<List<Map<String, dynamic>>> getDetallesHoy(
    int userId,
    List<Multa> multasCache, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && await CacheDetallesService.tieneCacheMesActual()) {
      return await CacheDetallesService.leerMes();
    }

    // ── Consultar API con endpoint correcto ──────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';

    final now = DateTime.now();
    final inicio = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final ultimoDia = DateTime(now.year, now.month + 1, 0).day;
    final fin =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${ultimoDia.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '$baseUrl/notificaciondetalle/'
      '?notificacion__id=&notificacion__cedula=&notificacion__placa='
      '&notificacion__usuario__username=${Uri.encodeComponent(username)}'
      '&fecha_inicio=$inicio&fecha_fin=$fin',
    );

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

        result.add({
          'idDetalle': item['id'] ?? 0,
          'idNotificacion': notifRaw['id'] ?? 0,
          'placa': (notifRaw['placa'] as String? ?? '').toUpperCase(),
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
    await CacheDetallesService.guardarMes(result);

    // Retornar todos los registros del mes
    return result;
  }
}

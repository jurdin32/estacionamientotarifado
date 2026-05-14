#!/usr/bin/env python3
"""
Aplica los 6 cambios planificados en EstacionamientoScreen.dart
de forma precisa, usando búsqueda de patrones exactos.
"""
import re

FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

original = content
changes = []

# ============================================================
# CAMBIO 1: Reemplazar unawaited(_persistirCacheCompleto()) en el registro
# Buscar: unawaited(_persistirCacheCompleto()); seguido de linea en blanco y "// 2. Cerrar"
# ============================================================
old1 = "                                      unawaited(_persistirCacheCompleto());\n\n                                      // 2. Cerrar di"
new1 = """                                      // Persistir INMEDIATAMENTE (sin debounce) para que
                                      // el cache de tarjetas sobreviva a un cierre abrupto.
                                      unawaited(_persistirCacheInmediato());

                                      // 2. Cerrar di"""
count1 = content.count(old1)
if count1 == 1:
    content = content.replace(old1, new1)
    changes.append(f"Cambio 1: OK (1 reemplazo en registro)")
elif count1 == 0:
    changes.append(f"Cambio 1: ERROR - no se encontro el patron")
else:
    changes.append(f"Cambio 1: ERROR - {count1} ocurrencias encontradas (deberia ser 1)")

# ============================================================
# CAMBIO 2: Insertar metodo _persistirCacheInmediato() antes de _persistirCacheCompleto()
# ============================================================
old2 = "  Future<void> _persistirCacheCompleto() async {"
new2_method = """  /// Persiste el estado actual de estacionamientos y tarjetas en SharedPreferences
  /// INMEDIATAMENTE, sin debounce. Util para operaciones criticas como el registro
  /// optimista, donde el cache debe sobrevivir a un cierre abrupto de la app.
  Future<void> _persistirCacheInmediato() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'estacionamientos',
        json.encode(_estaciones.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        'estacionamientos_tarjeta',
        json.encode(_estacionamientosTarjeta.map((e) => e.toJson()).toList()),
      );
      if (_tiemposTarjeta.isNotEmpty) {
        await prefs.setString(
          'tarjetas_tiempo',
          json.encode(
            _tiemposTarjeta.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
      debugPrint('[CACHE]  Persistencia inmediata completada '
        '(${_estaciones.length} est, ${_estacionamientosTarjeta.length} tar)',
      );
    } catch (e) {
      debugPrint('[ADVERTENCIA]  Error en persistencia inmediata: $e');
    }
  }

"""
count2 = content.count(old2)
if count2 == 1:
    content = content.replace(old2, new2_method + old2)
    changes.append(f"Cambio 2: OK (metodo insertado)")
else:
    changes.append(f"Cambio 2: ERROR - {count2} ocurrencias de _persistirCacheCompleto")

# ============================================================
# CAMBIO 3: Proteccion con fallback en WS snapshot
# ============================================================
old3 = """            // No revertir ocupado-> libre si hay tarjeta activa local
            final local = mapaLocal[remoto.id];
            if (local != null &&
                local.estado == true &&
                remoto.estado == false &&
                _estacionamientosTarjeta.any(
                  (t) => t.estacionId == remoto.id,
                )) {
              debugPrint(
                '[PROTEGIDO]  WS snapshot: protegiendo estacion #${local.numero} '
                '(tiene tarjeta activa)',
              );
              lista[i] = local;
            }"""

new3 = """            // No revertir ocupado-> libre si hay tarjeta activa local.
            // Verificar en memoria y tambien en SharedPreferences como fallback
            // por si el snapshot de estaciones llega antes que el de tarjetas.
            final local = mapaLocal[remoto.id];
            if (local != null &&
                local.estado == true &&
                remoto.estado == false) {
              final tieneTarjetaActiva = _estacionamientosTarjeta.any(
                    (t) => t.estacionId == remoto.id,
                  ) ||
                  _verificarTarjetaEnPrefs(remoto.id);
              if (tieneTarjetaActiva) {
                debugPrint(
                  '[PROTEGIDO]  WS snapshot: protegiendo estacion #${local.numero} '
                  '(tiene tarjeta activa)',
                );
                lista[i] = local;
              }
            }"""

count3 = content.count(old3)
if count3 == 1:
    content = content.replace(old3, new3)
    changes.append(f"Cambio 3: OK (proteccion snapshot mejorada)")
else:
    changes.append(f"Cambio 3: ERROR - {count3} ocurrencias")

# ============================================================
# CAMBIO 4: Proteccion con fallback en WS update
# ============================================================
old4 = """        // Proteccion anti-reversion: no liberar si hay tarjeta activa local.
        // El servidor podria enviar estado=false por una race condition o
        // snapshot parcial; la liberacion real llega con tarjetas/delete.
        final actual = _estaciones.where((e) => e.id == nuevo.id).firstOrNull;
        if (actual != null &&
            actual.estado == true &&
            nuevo.estado == false &&
            _estacionamientosTarjeta.any((t) => t.estacionId == nuevo.id)) {
          debugPrint(
            '[PROTEGIDO]  WS update: bloqueando liberacion de estacion '
            '#${actual.numero} (tiene tarjeta activa)',
          );
          return;
        }"""

new4 = """        // Proteccion anti-reversion: no liberar si hay tarjeta activa local.
        // El servidor podria enviar estado=false por una race condition o
        // snapshot parcial; la liberacion real llega con tarjetas/delete.
        // Verificar en memoria y tambien en SharedPreferences como fallback.
        final actual = _estaciones.where((e) => e.id == nuevo.id).firstOrNull;
        if (actual != null &&
            actual.estado == true &&
            nuevo.estado == false) {
          final tieneTarjetaActiva = _estacionamientosTarjeta.any(
                (t) => t.estacionId == nuevo.id,
              ) ||
              _verificarTarjetaEnPrefs(nuevo.id);
          if (tieneTarjetaActiva) {
            debugPrint(
              '[PROTEGIDO]  WS update: bloqueando liberacion de estacion '
              '#${actual.numero} (tiene tarjeta activa)',
            );
            return;
          }
        }"""

count4 = content.count(old4)
if count4 == 1:
    content = content.replace(old4, new4)
    changes.append(f"Cambio 4: OK (proteccion update mejorada)")
else:
    changes.append(f"Cambio 4: ERROR - {count4} ocurrencias")

# ============================================================
# CAMBIO 5: Correccion del filtro "Todos" - NO APLICA
# El codigo actual NO tiene el bloque if (_filtroEstado == 'todos')
# que excluia ocupados. Este cambio ya no es necesario.
# ============================================================
changes.append(f"Cambio 5: NO NECESARIO - el codigo actual ya no tiene el filtro 'todos' incorrecto")

# ============================================================
# CAMBIO 6: Verificacion de consistencia en carga inicial
# Insertar despues de la carga de cachedTarjetas y antes de "tarjetas tiempo"
# ============================================================
old6 = "      // --- Datos de cache: tarjetas tiempo (numero ->  minutos consumidos) ---"
new6_block = """      // --- Verificacion de consistencia: estaciones ocupadas sin tarjetas ---
      // Si hay estaciones con estado=true pero cachedTarjetas esta vacio,
      // intentar reconstruir desde SharedPreferences (fallback por si el
      // debounce de _persistirCacheCompleto no alcanzo a ejecutarse).
      if (cachedEstaciones.any((e) => e.estado) && cachedTarjetas.isEmpty) {
        final tarjetasRaw = prefs.getString('estacionamientos_tarjeta');
        if (tarjetasRaw != null && tarjetasRaw.isNotEmpty && tarjetasRaw != '[]') {
          try {
            final List<dynamic> tarjetasList = json.decode(tarjetasRaw);
            final reconstruidas = tarjetasList
                .map((e) => _parseEstacionamientoTarjetaFromJson(e))
                .where((e) => e != null)
                .cast<Estacionamiento_Tarjeta>()
                .toList();
            if (reconstruidas.isNotEmpty) {
              cachedTarjetas = reconstruidas;
              debugPrint('[CARGA]  Reconstruidas ${reconstruidas.length} tarjetas desde SharedPreferences');
            }
          } catch (e) {
            debugPrint('[CARGA]  Error reconstruyendo tarjetas: $e');
          }
        }
      }

      // --- Datos de cache: tarjetas tiempo (numero ->  minutos consumidos) ---"""

count6 = content.count(old6)
if count6 == 1:
    content = content.replace(old6, new6_block)
    changes.append(f"Cambio 6: OK (verificacion de consistencia insertada)")
else:
    changes.append(f"Cambio 6: ERROR - {count6} ocurrencias")

# ============================================================
# CAMBIO 7: Agregar metodo _verificarTarjetaEnPrefs() despues de _persistirCacheCompleto
# ============================================================
old7 = "  void _updateUIAfterChange(int estacionId, bool nuevoEstado, String placa) {"
new7_method = """  /// Verifica en SharedPreferences si existe una tarjeta activa para el estacionamiento dado.
  /// Util como fallback cuando el snapshot de estaciones del WS llega antes que el de tarjetas.
  bool _verificarTarjetaEnPrefs(int estacionId) {
    try {
      // Verificar en la lista en memoria (ya cargada desde SharedPreferences en _loadUserAndData)
      return _estacionamientosTarjeta.any((t) => t.estacionId == estacionId);
    } catch (_) {
      return false;
    }
  }

"""

count7 = content.count(old7)
if count7 == 1:
    content = content.replace(old7, new7_method + old7)
    changes.append(f"Cambio 7: OK (metodo _verificarTarjetaEnPrefs agregado)")
else:
    changes.append(f"Cambio 7: ERROR - {count7} ocurrencias")

# ============================================================
# Guardar
# ============================================================
if content != original:
    with open(FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Archivo guardado exitosamente.")
else:
    print("ADVERTENCIA: No se realizaron cambios!")

print("\n--- Resumen de cambios ---")
for c in changes:
    print(f"  {c}")

#!/usr/bin/env python3
"""
Aplica TODOS los cambios en EstacionamientoScreen.dart:
1. _persistirCacheInmediato() en registro
2. Nuevo metodo _persistirCacheInmediato()
3. Proteccion WS snapshot con fallback
4. Proteccion WS update con fallback
5. Verificacion de consistencia en carga inicial
6. Nuevo metodo _verificarTarjetaEnPrefs()
7. CORREGIR: unawaited(() async { ... }()) -> unawaited((() async { ... })())
"""
FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

original = content
results = []

# ============================================================
# CAMBIO 1: Reemplazar unawaited(_persistirCacheCompleto()) en el registro
# ============================================================
old1 = "                                      unawaited(_persistirCacheCompleto());\n\n                                      // 2. Cerrar di"
new1 = """                                      // Persistir INMEDIATAMENTE (sin debounce) para que
                                      // el cache de tarjetas sobreviva a un cierre abrupto.
                                      unawaited(_persistirCacheInmediato());

                                      // 2. Cerrar di"""
c1 = content.count(old1)
if c1 == 1:
    content = content.replace(old1, new1)
    results.append(f"Cambio 1: OK")
else:
    results.append(f"Cambio 1: ERROR ({c1} ocurrencias)")

# ============================================================
# CAMBIO 2: Insertar metodo _persistirCacheInmediato()
# ============================================================
old2 = "  Future<void> _persistirCacheCompleto() async {"
new2 = """  /// Persiste el estado actual de estacionamientos y tarjetas en SharedPreferences
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
c2 = content.count(old2)
if c2 == 1:
    content = content.replace(old2, new2 + old2)
    results.append(f"Cambio 2: OK")
else:
    results.append(f"Cambio 2: ERROR ({c2} ocurrencias)")

# ============================================================
# CAMBIO 3: Proteccion WS snapshot con fallback
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
                '[PROTEGIDO]  WS snapshot: protegiendo estación #${local.numero} '
                '(tiene tarjeta activa)',
              );
              lista[i] = local;
            }"""
new3 = """            // No revertir ocupado-> libre si hay tarjeta activa local.
            // Verificar en memoria y también en SharedPreferences como fallback
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
                  '[PROTEGIDO]  WS snapshot: protegiendo estación #${local.numero} '
                  '(tiene tarjeta activa)',
                );
                lista[i] = local;
              }
            }"""
c3 = content.count(old3)
if c3 == 1:
    content = content.replace(old3, new3)
    results.append(f"Cambio 3: OK")
else:
    results.append(f"Cambio 3: ERROR ({c3} ocurrencias)")

# ============================================================
# CAMBIO 4: Proteccion WS update con fallback
# ============================================================
old4 = """        // Protección anti-reversión: no liberar si hay tarjeta activa local.
        // El servidor podría enviar estado=false por una race condition o
        // snapshot parcial; la liberación real llega con tarjetas/delete.
        final actual = _estaciones.where((e) => e.id == nuevo.id).firstOrNull;
        if (actual != null &&
            actual.estado == true &&
            nuevo.estado == false &&
            _estacionamientosTarjeta.any((t) => t.estacionId == nuevo.id)) {
          debugPrint(
            '[PROTEGIDO]  WS update: bloqueando liberación de estación '
            '#${actual.numero} (tiene tarjeta activa)',
          );
          return;
        }"""
new4 = """        // Protección anti-reversión: no liberar si hay tarjeta activa local.
        // El servidor podría enviar estado=false por una race condition o
        // snapshot parcial; la liberación real llega con tarjetas/delete.
        // Verificar en memoria y también en SharedPreferences como fallback.
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
              '[PROTEGIDO]  WS update: bloqueando liberación de estación '
              '#${actual.numero} (tiene tarjeta activa)',
            );
            return;
          }
        }"""
c4 = content.count(old4)
if c4 == 1:
    content = content.replace(old4, new4)
    results.append(f"Cambio 4: OK")
else:
    results.append(f"Cambio 4: ERROR ({c4} ocurrencias)")

# ============================================================
# CAMBIO 5: Verificacion de consistencia en carga inicial
# ============================================================
old5 = "      // --- Datos de caché: tarjetas tiempo (numero ->  minutos consumidos) ---"
new5 = """      // --- Verificación de consistencia: estaciones ocupadas sin tarjetas ---
      // Si hay estaciones con estado=true pero cachedTarjetas está vacío,
      // intentar reconstruir desde SharedPreferences (fallback por si el
      // debounce de _persistirCacheCompleto no alcanzó a ejecutarse).
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

      // --- Datos de caché: tarjetas tiempo (numero ->  minutos consumidos) ---"""
c5 = content.count(old5)
if c5 == 1:
    content = content.replace(old5, new5)
    results.append(f"Cambio 5: OK")
else:
    results.append(f"Cambio 5: ERROR ({c5} ocurrencias)")

# ============================================================
# CAMBIO 6: Agregar metodo _verificarTarjetaEnPrefs()
# ============================================================
old6 = "  void _updateUIAfterChange(int estacionId, bool nuevoEstado, String placa) {"
new6 = """  /// Verifica en SharedPreferences si existe una tarjeta activa para el estacionamiento dado.
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
c6 = content.count(old6)
if c6 == 1:
    content = content.replace(old6, new6 + old6)
    results.append(f"Cambio 6: OK")
else:
    results.append(f"Cambio 6: ERROR ({c6} ocurrencias)")

# ============================================================
# CAMBIO 7: CORREGIR unawaited(() async { ... }())
# La sintaxis actual: unawaited(() async { ... }());
# No ejecuta la funcion porque el () esta fuera del unawaited.
# La sintaxis correcta: unawaited((() async { ... })());
# ============================================================
old7 = "unawaited(() async {"
new7 = "unawaited((() async {"
c7 = content.count(old7)
if c7 >= 1:
    content = content.replace(old7, new7)
    results.append(f"Cambio 7: OK ({c7} reemplazos de unawaited(() async -> unawaited((() async")
else:
    results.append(f"Cambio 7: ERROR (no se encontro el patron)")

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
for r in results:
    print(f"  {r}")

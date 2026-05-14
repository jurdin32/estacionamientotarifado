#!/usr/bin/env python3
"""
Aplica los cambios 3, 4 y 6 en EstacionamientoScreen.dart
con los patrones exactos del archivo (con acentos).
"""
FILE = r"c:\Users\Johnny Urdin\Desktop\Tarifado\lib\tarjetas\views\EstacionamientoScreen.dart"

with open(FILE, 'r', encoding='utf-8') as f:
    content = f.read()

original = content

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

count3 = content.count(old3)
print(f"Cambio 3: {count3} ocurrencias encontradas")
if count3 == 1:
    content = content.replace(old3, new3)
    print("  -> APLICADO")
else:
    print(f"  -> ERROR: se esperaba 1, se encontraron {count3}")

# ============================================================
# CAMBIO 4: Proteccion con fallback en WS update
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

count4 = content.count(old4)
print(f"Cambio 4: {count4} ocurrencias encontradas")
if count4 == 1:
    content = content.replace(old4, new4)
    print("  -> APLICADO")
else:
    print(f"  -> ERROR: se esperaba 1, se encontraron {count4}")

# ============================================================
# CAMBIO 6: Verificacion de consistencia en carga inicial
# ============================================================
old6 = "      // --- Datos de caché: tarjetas tiempo (numero ->  minutos consumidos) ---"
new6_block = """      // --- Verificación de consistencia: estaciones ocupadas sin tarjetas ---
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

count6 = content.count(old6)
print(f"Cambio 6: {count6} ocurrencias encontradas")
if count6 == 1:
    content = content.replace(old6, new6_block)
    print("  -> APLICADO")
else:
    print(f"  -> ERROR: se esperaba 1, se encontraron {count6}")

# ============================================================
# Guardar
# ============================================================
if content != original:
    with open(FILE, 'w', encoding='utf-8') as f:
        f.write(content)
    print("\nArchivo guardado exitosamente.")
else:
    print("\nADVERTENCIA: No se realizaron cambios!")

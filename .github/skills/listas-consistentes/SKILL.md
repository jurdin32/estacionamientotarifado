---
name: listas-consistentes
description: "Use when implementing or refactoring Flutter lists so all list items share the same visual card style used in control de tarjetas: gradient header, compact body, consistent chips and actions. Keywords: list style, card list, consistent items, Flutter list UI, control tarjetas style."
---

# Listas Consistentes

## Objetivo

Hacer que todas las listas de módulos usen la misma presentación visual que control de tarjetas, excepto el propio módulo de control que ya es referencia.

## Patrón recomendado

1. Reutilizar un widget de tarjeta compartido para cada ítem de lista.
2. Mantener encabezado con gradiente + avatar/identificador + badge de estado.
3. Mantener cuerpo compacto con chips informativos y acciones al final.
4. Usar paddings y radios consistentes entre módulos.
5. Evitar estilos de Card diferentes en cada pantalla.

## Referencia en este proyecto

- Widget base: lib/shared/widgets/tarjeta_lista_app.dart
- Módulo referencia: lib/tarjetas/views/EstacionamientoScreen.dart

## Checklist

- Todas las listas usan la misma jerarquía visual.
- Ítems tienen encabezado con acento de color contextual.
- El cuerpo no usa alturas excesivas ni spacing irregular.
- Acciones (editar, borrar, entrar) usan iconografía y tamaño consistentes.
- Control de tarjetas se mantiene como referencia y no se degrada.

## Ejemplo

```dart
TarjetaListaApp(
  colorAcento: const Color(0xFF1565C0),
  avatar: _avatar,
  titulo: 'Usuario',
  subtitulo: '@admin',
  encabezadoDerecha: _badgeEstado,
  cuerpo: _contenido,
  onTap: _onTap,
)
```
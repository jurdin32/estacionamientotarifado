---
name: encabezado-consistente
description: "Use when implementing or refactoring Flutter module headers so all screens use the same compact SIMERT identity band with shared widget, consistent spacing, and responsive scaling on phones, tablets and desktop/windows. Keywords: header, SIMERT band, compact top section, responsive module title, Flutter UI consistency."
---

# Encabezado Consistente

## Objetivo

Estandarizar la franja superior de módulos con una identidad visual única, compacta y reutilizable.

## Patrón recomendado

1. Usar un widget compartido para el encabezado, no copiar Container + Row en cada pantalla.
2. Mantener jerarquía fija: icono circular, título SIMERT y subtítulo del módulo.
3. Usar espaciado compacto: padding superior controlado y separación horizontal estable.
4. Ajustar tipografía e icono por breakpoints para evitar tamaños desproporcionados.
5. Mantener color único de encabezado entre pantallas: AppBar y banda SIMERT deben usar `AppColores.gradientePrincipal` salvo casos excepcionales justificados.
6. Los diálogos de información también deben usar `AppColores.gradientePrincipal` en su encabezado para no romper la consistencia visual.

## Referencia en este proyecto

- Widget base: lib/shared/widgets/encabezado_modulo_app.dart

## Checklist

- El encabezado no está duplicado manualmente.
- El título no desborda en pantallas estrechas.
- El subtítulo mantiene legibilidad en móvil y escritorio.
- El icono y texto escalan de forma moderada por dispositivo.
- El color del encabezado coincide con el estándar visual de Consultas en todos los módulos.
- Los popups de información no usan gradientes alternos ni tonos distintos al estándar.

## Ejemplo

```dart
const EncabezadoModuloApp(
  icono: Icons.gavel,
  subtitulo: 'Sistema de Multas Electrónicas',
)
```
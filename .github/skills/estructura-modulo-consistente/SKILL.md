---
name: estructura-modulo-consistente
description: "Use when building Flutter module pages with search and content so each screen follows the same compact structure: app bar, SIMERT header band, compact search block, filters, and body states. Keywords: module layout, compact structure, search panel, responsive Flutter page, phones tablets windows."
---

# Estructura de Módulo Consistente

## Objetivo

Repetir una misma estructura visual entre módulos para reducir ruido y mejorar percepción de calidad.

## Estructura base

1. AppBar con acciones mínimas.
2. Encabezado SIMERT compacto reutilizable.
3. Bloque de búsqueda compacto (campo + acciones necesarias).
4. Filtros o tabs de estado.
5. Body con estados claros: cargando, error, vacío, contenido.

## Reglas de implementación

1. Reutilizar widgets compartidos (`EncabezadoModuloApp`, `CampoBusquedaApp`, `EstadoCargaApp`).
2. Para ítems de listas, usar `TarjetaListaApp` para mantener el estilo uniforme basado en control de tarjetas.
3. Evitar paddings arbitrarios grandes en la zona superior.
4. Mantener alturas de controles compactas en móvil.
5. En tablet y escritorio, preservar la misma jerarquía sin inflar tamaños.
6. En módulos con rol administrador y listados globales, incluir filtro por rango de fechas y filtro por usuario emisor.
7. Si existe conjunto finito de usuarios, preferir selector desplegable en lugar de entrada manual por ID.
8. Mostrar etiquetas amigables en el selector (username/nombre) y dejar el ID como referencia secundaria.
9. Si el módulo usa `showDateRangePicker` o diálogos Material, asegurar que la app tenga `localizationsDelegates` Material/Widgets/Cupertino y `supportedLocales` que incluyan español.
10. En listados de multas, incluir filtro por placa para acelerar auditoría operativa.
11. La edición de características de multa (literal/valor) debe estar restringida a administrador y solo en estados impaga o impugnada.

## Checklist

- El módulo respeta la secuencia visual completa.
- El bloque superior no se ve sobredimensionado.
- Búsqueda, filtros y body conservan espaciado homogéneo.
- Estados de carga/error/vacío usan componentes compartidos.
- Las listas usan el mismo estilo visual de tarjeta entre módulos.
- En vistas administrativas existen filtros claros para auditar por fecha y usuario.
- En filtros de usuario administrativos se evita escribir IDs manuales cuando puede seleccionarse desde lista.
- El dropdown de usuarios muestra nombre legible para acelerar auditorías.
- Si hay selector de fechas Material, no debe aparecer el error `No MaterialLocalizations found`.
- En módulos de multas existe búsqueda por placa con patrón compacto reutilizable.
- Si se permite editar literal/valor, el valor se autocompleta desde el literal seleccionado y no se habilita para operadores sin rol admin.
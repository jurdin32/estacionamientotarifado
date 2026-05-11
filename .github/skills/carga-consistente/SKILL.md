---
name: carga-consistente
description: "Use when implementing or refactoring Flutter loading states and responsive behavior so all full-screen waits use the same branded SIMERT style and layouts adapt correctly on phones, tablets, and desktop/windows devices. Keywords: loading state, pantalla de carga, responsive, adaptativo, breakpoints, tablet, windows, Flutter consistency."
---

# Carga Consistente y Responsiva

## Objetivo

Mantener una experiencia uniforme de espera en todo el proyecto usando un solo componente visual para cargas de pantalla completa y asegurar que la UI se adapte a distintos tamaños de pantalla.

## Patron recomendado

1. Usar el widget compartido de carga en vez de construir Column/Center manualmente en cada pantalla.
2. Mostrar icono semántico de la pantalla y un mensaje específico de la operación.
3. Conservar estilo visual de marca: círculo con gradiente, texto SIMERT y barra de progreso inferior.
4. Personalizar colores solo cuando la pantalla tenga una variante visual justificada.
5. Aplicar puntos de corte responsive para móviles, tablets y escritorio/windows.
6. Evitar medidas fijas rígidas; usar escalas y utilidades responsive.

## Reglas de responsividad por dispositivo

1. Telefonos: ancho menor a 600, prioridad en contenido vertical, paddings compactos y textos base.
2. Tablets: ancho entre 600 y 1199, aumentar espaciados y tipografías de forma moderada.
3. Windows y escritorio: ancho mayor o igual a 1200, centrar contenido y limitar ancho máximo para legibilidad.
4. Mantener objetivos táctiles de al menos 48x48 en cualquier plataforma.
5. Soportar entrada táctil y mouse/trackpad (scroll y drag adaptados).
6. No romper layout en orientación horizontal.

## Recomendaciones Android 15/16 (Google Play)

1. Android 15 (targetSdk 35): la app se muestra edge-to-edge por defecto, por lo que cada pantalla debe manejar insets correctamente.
2. Evitar APIs obsoletas de barras del sistema: no usar setStatusBarColor, setNavigationBarColor ni setNavigationBarDividerColor.
3. En Flutter, preferir SystemUiMode.edgeToEdge y evitar configuraciones que intenten fijar colores de barras vía APIs antiguas.
4. Android 16 y pantallas grandes: no forzar orientación/bloqueos de tamaño en activities (foldables, tablets, ventanas grandes).
5. Si una dependencia declara orientación fija (ej. CaptureActivity), sobrescribirla a unspecified para compatibilidad en gran pantalla.

## Checklist Android

- MainActivity permite resize y no bloquea orientación.
- No se aplican colores de status/navigation bar con APIs deprecadas.
- Edge-to-edge está habilitado y probado en Android 15+.
- Activities de terceros con orientación forzada están corregidas por manifest override cuando aplique.
- Validado visualmente en teléfono, tablet y ventana ancha (Windows/ChromeOS/DeX).

## Referencia en este proyecto

- Widget base: lib/shared/widgets/estado_carga_app.dart
- Utilidades responsive: lib/core/constantes.dart (Responsive)
- Adaptador global: lib/main.dart (_AdaptadorResponsiveGlobal)

## Checklist

- Existe un estado booleano de carga claro (_isLoading, _cargando, loading).
- El estado de pantalla completa usa EstadoCargaApp.
- El mensaje de carga describe la acción actual.
- El icono representa el módulo (vehículos, usuarios, notificaciones, etc.).
- Se evita duplicar layouts de carga entre pantallas.
- El layout cambia correctamente según breakpoints (movil/tablet/escritorio).
- En escritorio/windows se aplica ancho máximo centrado para evitar líneas excesivamente largas.
- Scroll y drag funcionan en touch y mouse.

## Ejemplo

```dart
if (_isLoading) {
  return const EstadoCargaApp(
    icono: Icons.people_alt_rounded,
    mensaje: 'Cargando beneficiarios…',
    colorInicio: AppColores.primario,
    colorFin: AppColores.acentoAdmin,
  );
}
```

## Reutilizacion en otros repositorios

Para futuros proyectos, copiar esta skill, el widget compartido de carga y las utilidades responsive al nuevo repositorio.
---
name: busqueda-consistente
description: "Use when implementing or refactoring Flutter search UIs so every search field keeps the search icon inside the field on the right, supports Enter to trigger the search, and follows a compact and reusable structure across the whole interface in phones, tablets and desktop/windows. Keywords: search field, buscar, Enter, compact UI, responsive search panel, trailing search icon, Flutter search UX."
---

# Busqueda Consistente y Compacta

## Objetivo

Unificar las busquedas en Flutter con estas reglas:

- El icono de buscar vive dentro del campo, al lado derecho.
- Presionar Enter activa la busqueda.
- Limpiar texto no elimina el acceso rapido a buscar.
- El patron debe ser reutilizable, no copiado pantalla por pantalla.
- La estructura visual debe ser compacta y consistente en toda la interfaz.

## Patron recomendado

1. Crear o reutilizar un widget compartido de busqueda.
2. Configurar `textInputAction: TextInputAction.search`.
3. Ejecutar la misma accion tanto en `onSubmitted` como en el boton de buscar del `suffixIcon`.
4. Si la pantalla filtra en vivo, Enter debe al menos confirmar el filtro y cerrar teclado.
5. Evitar botones de buscar separados debajo del campo cuando el icono interno ya dispara la accion principal.
6. Usar espaciado compacto en bloques de busqueda: paddings de 10 a 12 y separaciones verticales de 8 a 10.
7. Mantener alturas de accion compactas (por ejemplo 44) para que el bloque no se vea sobredimensionado.
8. Ajustar el bloque en responsive: telefono compacto, tablet moderado, escritorio con ancho contenido controlado.
9. En módulos administrativos, el campo también puede usarse para filtrar por identificador de usuario sin romper el patrón visual.
10. Si el bloque de filtros incluye `showDateRangePicker`, verificar que `MaterialApp` tenga delegates de localización Material/Widgets/Cupertino y locales en español para evitar fallos de diálogo.

## Referencia en este proyecto

- Widget compartido: `lib/shared/widgets/campo_busqueda_app.dart`

## Checklist de aplicacion

- El campo tiene icono de buscar a la derecha.
- El campo responde a Enter.
- El boton de limpiar es opcional, pero no reemplaza al de buscar.
- El estilo del campo usa los colores del tema del proyecto.
- La pantalla no duplica la accion principal con otro boton de buscar innecesario.
- El bloque de busqueda no se ve sobredimensionado en movil.
- En tablet y escritorio la estructura conserva jerarquia visual sin crecer de forma exagerada.
- Si la pantalla es administrativa, el filtro por usuario respeta el mismo campo compacto con icono interno y Enter.
- Si la pantalla abre selector de rango de fechas, no debe fallar por ausencia de `MaterialLocalizations`.

## Ejemplo

```dart
CampoBusquedaApp(
  controller: controller,
  labelText: 'Buscar usuario',
  hintText: 'Nombre, correo o placa',
  onSearch: _buscar,
  onChanged: (_) => setState(() {}),
  onClear: () => setState(() {}),
)
```

## Nota de reutilizacion

Los skills solo viven a nivel de workspace dentro de `.github/skills/`. Para usar este patron en futuros proyectos, copia esta carpeta y el widget compartido al nuevo repositorio.
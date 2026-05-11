import 'package:flutter/material.dart';
import '../../core/colores.dart';
import '../../core/constantes.dart';

/// Campo de texto reutilizable con validación completa.
/// Soporta: contraseña, autofocus, limpiar, textAction, contador, disabled.
class CampoTextoApp extends StatefulWidget {
  const CampoTextoApp({
    super.key,
    required this.controller,
    required this.etiqueta,
    required this.icono,
    this.esContrasena = false,
    this.mostrarContrasena = false,
    this.onToggleContrasena,
    this.validador,
    this.tipoTeclado,
    this.accionTeclado,
    this.onAccion,
    this.autoFocus = false,
    this.mostrarLimpiar = false,
    this.maxLongitud,
    this.deshabilitado = false,
    this.textoAyuda,
    this.floatingLabelBehavior,
    this.colorTexto,
    this.colorIcono,
    this.colorEtiqueta,
    this.colorFondo,
  });

  final TextEditingController controller;
  final String etiqueta;
  final IconData icono;
  final bool esContrasena;
  final bool mostrarContrasena;
  final VoidCallback? onToggleContrasena;
  final String? Function(String?)? validador;
  final TextInputType? tipoTeclado;
  final TextInputAction? accionTeclado;
  final VoidCallback? onAccion;
  final bool autoFocus;
  final bool mostrarLimpiar;
  final int? maxLongitud;
  final bool deshabilitado;
  final String? textoAyuda;
  final FloatingLabelBehavior? floatingLabelBehavior;
  final Color? colorTexto;
  final Color? colorIcono;
  final Color? colorEtiqueta;
  final Color? colorFondo;

  @override
  State<CampoTextoApp> createState() => _CampoTextoAppState();
}

class _CampoTextoAppState extends State<CampoTextoApp> {
  bool _tieneTexto = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCambio);
  }

  void _onCambio() {
    final tiene = widget.controller.text.isNotEmpty;
    if (tiene != _tieneTexto) setState(() => _tieneTexto = tiene);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCambio);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorTexto = widget.colorTexto ?? AppColores.textoPrimario;
    final colorIcono = widget.colorIcono ?? AppColores.textoSecundario;
    final colorFondo =
        widget.colorFondo ??
        theme.inputDecorationTheme.fillColor ??
        Colors.white;

    Widget? sufijo;
    if (widget.esContrasena) {
      sufijo = IconButton(
        icon: Icon(
          widget.mostrarContrasena ? Icons.visibility : Icons.visibility_off,
          color: colorIcono,
          size: 20,
        ),
        onPressed: widget.onToggleContrasena,
      );
    } else if (widget.mostrarLimpiar && _tieneTexto) {
      sufijo = IconButton(
        icon: Icon(Icons.clear, color: colorIcono, size: 20),
        onPressed: () => widget.controller.clear(),
      );
    }

    return TextFormField(
      controller: widget.controller,
      obscureText: widget.esContrasena && !widget.mostrarContrasena,
      keyboardType: widget.tipoTeclado,
      textInputAction: widget.accionTeclado,
      autofocus: widget.autoFocus,
      enabled: !widget.deshabilitado,
      maxLength: widget.maxLongitud,
      style: TextStyle(color: colorTexto),
      validator: widget.validador,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onFieldSubmitted: widget.onAccion != null
          ? (_) => widget.onAccion!()
          : null,
      decoration: InputDecoration(
        filled: true,
        fillColor: widget.deshabilitado
            ? AppColores.borde.withValues(alpha: 0.3)
            : colorFondo,
        labelText: widget.etiqueta,
        labelStyle: TextStyle(color: widget.colorEtiqueta ?? colorIcono),
        floatingLabelBehavior: widget.floatingLabelBehavior,
        helperText: widget.textoAyuda,
        helperStyle: const TextStyle(
          fontSize: 12,
          color: AppColores.textoSecundario,
        ),
        counterStyle: const TextStyle(
          fontSize: 11,
          color: AppColores.textoTerciario,
        ),
        prefixIcon: Icon(widget.icono, color: colorIcono, size: 20),
        suffixIcon: sufijo,
        border: OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(
            color: colorIcono.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide.none,
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.error, width: 1.5),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.error, width: 2),
        ),
        errorStyle: const TextStyle(color: AppColores.error, fontSize: 12),
      ),
    );
  }
}

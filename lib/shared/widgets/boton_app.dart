import 'package:flutter/material.dart';
import '../../core/colores.dart';
import '../../core/constantes.dart';

/// Variantes del botón
enum VarianteBoton { primario, secundario, outline, texto, peligro }

/// Tamaños del botón
enum TamanoBoton { pequeno, mediano, grande }

/// Botón reutilizable con variantes, tamaños, ícono y estados.
/// Tamaño mínimo 48x48dp para accesibilidad.
class BotonApp extends StatelessWidget {
  const BotonApp({
    super.key,
    required this.texto,
    required this.onPressed,
    this.variante = VarianteBoton.primario,
    this.tamano = TamanoBoton.mediano,
    this.cargando = false,
    this.habilitado = true,
    this.ancho,
    this.iconoIzquierda,
    this.iconoDerecha,
  });

  final String texto;
  final VoidCallback? onPressed;
  final VarianteBoton variante;
  final TamanoBoton tamano;
  final bool cargando;
  final bool habilitado;
  final double? ancho;
  final IconData? iconoIzquierda;
  final IconData? iconoDerecha;

  double get _altura => switch (tamano) {
    TamanoBoton.pequeno => 36,
    TamanoBoton.mediano => 48,
    TamanoBoton.grande => 56,
  };

  double get _fontSize => switch (tamano) {
    TamanoBoton.pequeno => 13,
    TamanoBoton.mediano => 15,
    TamanoBoton.grande => 16,
  };

  double get _iconSize => switch (tamano) {
    TamanoBoton.pequeno => 16,
    TamanoBoton.mediano => 18,
    TamanoBoton.grande => 20,
  };

  @override
  Widget build(BuildContext context) {
    final activo = habilitado && !cargando;
    final child = _buildChild();

    Widget boton = switch (variante) {
      VarianteBoton.outline => OutlinedButton(
        onPressed: activo ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(ancho ?? 48, _altura),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(
            color: activo ? AppColores.acento : AppColores.textoTerciario,
            width: 1.5,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadio.lg),
          textStyle: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      ),
      VarianteBoton.texto => TextButton(
        onPressed: activo ? onPressed : null,
        style: TextButton.styleFrom(
          minimumSize: Size(ancho ?? 48, _altura),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const RoundedRectangleBorder(borderRadius: AppRadio.lg),
          textStyle: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      ),
      _ => ElevatedButton(
        onPressed: activo ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _colorFondo(activo),
          foregroundColor: _colorTexto(),
          disabledBackgroundColor: AppColores.textoTerciario.withValues(
            alpha: 0.3,
          ),
          minimumSize: Size(ancho ?? 48, _altura),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const RoundedRectangleBorder(borderRadius: AppRadio.lg),
          elevation: AppElevacion.pequena,
          shadowColor: _colorFondo(activo).withValues(alpha: 0.35),
          textStyle: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: child,
      ),
    };

    return ancho != null
        ? SizedBox(width: ancho, height: _altura, child: boton)
        : boton;
  }

  Color _colorFondo(bool activo) => switch (variante) {
    VarianteBoton.peligro =>
      activo ? AppColores.error : AppColores.textoTerciario,
    VarianteBoton.secundario => AppColores.acentoFondoFuerte,
    _ => activo ? AppColores.acento : AppColores.textoTerciario,
  };

  Color _colorTexto() => switch (variante) {
    VarianteBoton.secundario => AppColores.primario,
    _ => Colors.white,
  };

  Widget _buildChild() {
    if (cargando) {
      return SizedBox(
        width: _iconSize,
        height: _iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: variante == VarianteBoton.secundario
              ? AppColores.acento
              : Colors.white,
        ),
      );
    }
    if (iconoIzquierda == null && iconoDerecha == null) return Text(texto);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconoIzquierda != null) ...[
          Icon(iconoIzquierda, size: _iconSize),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(texto),
        if (iconoDerecha != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(iconoDerecha, size: _iconSize),
        ],
      ],
    );
  }
}

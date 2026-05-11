import 'package:flutter/material.dart';
import '../../core/colores.dart';
import '../../core/constantes.dart';

/// Variantes de tarjeta
enum VarianteTarjeta { elevada, outline, sinBorde }

/// Tarjeta reutilizable con variantes, padding consistente y onTap opcional.
/// Soporta modo oscuro automáticamente a través del tema.
class TarjetaApp extends StatelessWidget {
  const TarjetaApp({
    super.key,
    required this.hijo,
    this.variante = VarianteTarjeta.elevada,
    this.radio = AppRadio.lg,
    this.onTap,
    this.padding,
    this.margen,
    this.color,
    this.elevation,
  });

  final Widget hijo;
  final VarianteTarjeta variante;
  final BorderRadius radio;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margen;
  final Color? color;
  final double? elevation;

  @override
  Widget build(BuildContext context) {
    final colorTarjeta =
        color ?? Theme.of(context).cardTheme.color ?? AppColores.tarjeta;
    final pad = padding ?? AppSpacing.cardPadding;

    return switch (variante) {
      VarianteTarjeta.outline => _buildOutline(context, colorTarjeta, pad),
      VarianteTarjeta.sinBorde => _buildSinBorde(context, colorTarjeta, pad),
      _ => _buildElevada(context, colorTarjeta, pad),
    };
  }

  Widget _buildElevada(
    BuildContext context,
    Color colorTarjeta,
    EdgeInsetsGeometry pad,
  ) {
    return Card(
      color: colorTarjeta,
      elevation: elevation ?? AppElevacion.tarjeta,
      margin: margen ?? EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radio),
      clipBehavior: Clip.antiAlias,
      child: _contenido(pad),
    );
  }

  Widget _buildOutline(
    BuildContext context,
    Color colorTarjeta,
    EdgeInsetsGeometry pad,
  ) {
    return Container(
      margin: margen ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: colorTarjeta,
        borderRadius: radio,
        border: Border.all(color: AppColores.borde),
      ),
      clipBehavior: Clip.antiAlias,
      child: _contenido(pad),
    );
  }

  Widget _buildSinBorde(
    BuildContext context,
    Color colorTarjeta,
    EdgeInsetsGeometry pad,
  ) {
    return Container(
      margin: margen ?? EdgeInsets.zero,
      decoration: BoxDecoration(color: colorTarjeta, borderRadius: radio),
      clipBehavior: Clip.antiAlias,
      child: _contenido(pad),
    );
  }

  Widget _contenido(EdgeInsetsGeometry pad) {
    final content = Padding(padding: pad, child: hijo);
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: radio, child: content);
  }
}

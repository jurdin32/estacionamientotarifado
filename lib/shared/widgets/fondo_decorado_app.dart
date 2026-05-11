import 'package:estacionamientotarifado/core/colores.dart';
import 'package:flutter/material.dart';

class FondoDecoradoApp extends StatelessWidget {
  const FondoDecoradoApp({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColores.gradienteHero,
            ),
          ),
        ),
        Positioned(
          top: -size.width * 0.16,
          right: -size.width * 0.18,
          child: Container(
            width: size.width * 0.62,
            height: size.width * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
        ),
        Positioned(
          top: size.height * 0.16,
          left: -size.width * 0.22,
          child: Transform.rotate(
            angle: -0.45,
            child: Container(
              width: size.width * 0.58,
              height: size.width * 0.58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(48),
                color: AppColores.acento.withValues(alpha: 0.16),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -size.width * 0.28,
          right: -size.width * 0.18,
          child: Container(
            width: size.width * 0.8,
            height: size.width * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }
}

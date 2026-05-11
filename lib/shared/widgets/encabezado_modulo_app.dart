import 'package:estacionamientotarifado/core/colores.dart';
import 'package:estacionamientotarifado/core/constantes.dart';
import 'package:flutter/material.dart';

class EncabezadoModuloApp extends StatelessWidget {
  const EncabezadoModuloApp({
    super.key,
    required this.icono,
    required this.subtitulo,
    this.titulo = 'SIMERT',
    this.gradiente,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Gradient? gradiente;

  @override
  Widget build(BuildContext context) {
    final iconSize = Responsive.valor<double>(
      context,
      mobil: 20,
      tablet: 22,
      escritorio: 24,
    );
    final titleSize = Responsive.valor<double>(
      context,
      mobil: 20,
      tablet: 22,
      escritorio: 23,
    );
    final subtitleSize = Responsive.valor<double>(
      context,
      mobil: 12,
      tablet: 13,
      escritorio: 13.5,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        gradient: gradiente as LinearGradient? ?? AppColores.gradientePrincipal,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: Colors.white, size: iconSize),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: subtitleSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

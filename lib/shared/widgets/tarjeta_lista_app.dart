import 'package:flutter/material.dart';

class TarjetaListaApp extends StatelessWidget {
  const TarjetaListaApp({
    super.key,
    required this.colorAcento,
    required this.avatar,
    required this.titulo,
    required this.cuerpo,
    this.subtitulo,
    this.encabezadoDerecha,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(vertical: 6),
  });

  final Color colorAcento;
  final Widget avatar;
  final String titulo;
  final String? subtitulo;
  final Widget? encabezadoDerecha;
  final Widget cuerpo;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final start = _oscurecer(colorAcento, 0.22);

    return Card(
      margin: margin,
      elevation: 4,
      shadowColor: colorAcento.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [start, colorAcento],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (subtitulo != null && subtitulo!.isNotEmpty)
                          Text(
                            subtitulo!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (encabezadoDerecha != null) encabezadoDerecha!,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: cuerpo,
            ),
          ],
        ),
      ),
    );
  }

  Color _oscurecer(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final next = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return next.toColor();
  }
}

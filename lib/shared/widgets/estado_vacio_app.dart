import 'package:estacionamientotarifado/core/colores.dart';
import 'package:estacionamientotarifado/core/constantes.dart';
import 'package:flutter/material.dart';

class EstadoVacioApp extends StatelessWidget {
  const EstadoVacioApp({
    super.key,
    required this.mensaje,
    this.icono = Icons.inbox_outlined,
    this.accionTexto,
    this.onAccion,
  });

  final String mensaje;
  final IconData icono;
  final String? accionTexto;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) {
    final iconSize = Responsive.valor<double>(
      context,
      mobil: 48,
      tablet: 54,
      escritorio: 56,
    );
    final textSize = Responsive.valor<double>(
      context,
      mobil: 15,
      tablet: 16,
      escritorio: 16,
    );
    final bubblePadding = Responsive.valor<double>(
      context,
      mobil: 18,
      tablet: 20,
      escritorio: 22,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(bubblePadding),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: iconSize, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 14),
            Text(
              mensaje,
              style: TextStyle(
                fontSize: textSize,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (accionTexto != null && onAccion != null) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColores.primario,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onAccion,
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(accionTexto!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

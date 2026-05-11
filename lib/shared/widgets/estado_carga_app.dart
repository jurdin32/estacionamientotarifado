import 'package:estacionamientotarifado/core/colores.dart';
import 'package:estacionamientotarifado/core/constantes.dart';
import 'package:flutter/material.dart';

class EstadoCargaApp extends StatelessWidget {
  const EstadoCargaApp({
    super.key,
    required this.icono,
    required this.mensaje,
    this.titulo = 'SIMERT',
    this.colorInicio = AppColores.primario,
    this.colorFin = AppColores.acentoAdmin,
    this.colorProgreso,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;
  final Color colorInicio;
  final Color colorFin;
  final Color? colorProgreso;

  @override
  Widget build(BuildContext context) {
    final escalaTexto = Responsive.escalaTipografia(context);
    final escalaEspacio = Responsive.escalaEspaciado(context);
    final iconSize = Responsive.valor<double>(
      context,
      mobil: 40,
      tablet: 48,
      escritorio: 56,
    );
    final paddingCirculo = Responsive.valor<double>(
      context,
      mobil: 24,
      tablet: 28,
      escritorio: 32,
    );
    final anchoBarra = Responsive.valor<double>(
      context,
      mobil: 220,
      tablet: 280,
      escritorio: 340,
    );

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(paddingCirculo),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorInicio, colorFin],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: iconSize, color: Colors.white),
          ),
          SizedBox(height: 20 * escalaEspacio),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 20 * escalaTexto,
              fontWeight: FontWeight.bold,
              color: colorInicio,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 8 * escalaEspacio),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13 * escalaTexto,
              color: AppColores.textoSecundario,
            ),
          ),
          SizedBox(height: 20 * escalaEspacio),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * escalaEspacio),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: anchoBarra),
              child: LinearProgressIndicator(
                backgroundColor: AppColores.divisor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorProgreso ?? colorFin,
                ),
                minHeight: 3,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

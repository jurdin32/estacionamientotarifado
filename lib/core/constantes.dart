import 'package:flutter/material.dart';

/// Espaciado consistente: 4, 8, 12, 16, 24, 32, 48
abstract final class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  static const EdgeInsets screenPadding = EdgeInsets.all(lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: md,
  );
}

/// Elevaciones consistentes
abstract final class AppElevacion {
  static const double ninguna = 0.0;
  static const double sutil = 1.0;
  static const double pequena = 2.0;
  static const double mediana = 4.0;
  static const double grande = 8.0;
  static const double extraGrande = 16.0;

  static const double tarjeta = 2.0;
  static const double desplegable = 8.0;
  static const double dialogo = 24.0;
  static const double fab = 6.0;
}

/// Radios de borde consistentes: 4, 8, 12, 16, 24
abstract final class AppRadio {
  static const BorderRadius ninguno = BorderRadius.zero;
  static const BorderRadius xs = BorderRadius.all(Radius.circular(4));
  static const BorderRadius sm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius md = BorderRadius.all(Radius.circular(12));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(16));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(24));
  static const BorderRadius completo = BorderRadius.all(Radius.circular(100));
}

/// Utilidades responsive según puntos de corte de las reglas
abstract final class Responsive {
  static const double quiebreMobil = 600;
  static const double quiebreTablet = 1200;
  static const double anchoMaxContenido = 1280;

  static bool esMobil(BuildContext context) =>
      MediaQuery.of(context).size.width < quiebreMobil;

  static bool esTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= quiebreMobil && w < quiebreTablet;
  }

  static bool esEscritorio(BuildContext context) =>
      MediaQuery.of(context).size.width >= quiebreTablet;

  static bool esHorizontal(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  /// Devuelve un valor diferente según el tipo de dispositivo
  static T valor<T>(
    BuildContext context, {
    required T mobil,
    required T tablet,
    T? escritorio,
  }) {
    if (esEscritorio(context)) return escritorio ?? tablet;
    if (esTablet(context)) return tablet;
    return mobil;
  }

  static double anchoPantalla(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double altoPantalla(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double escalaTipografia(BuildContext context) {
    final width = anchoPantalla(context);
    if (width < quiebreMobil) return 1.0;
    if (width < quiebreTablet) return 1.08;
    return 1.15;
  }

  static double escalaEspaciado(BuildContext context) {
    final width = anchoPantalla(context);
    if (width < quiebreMobil) return 1.0;
    if (width < quiebreTablet) return 1.15;
    return 1.25;
  }
}

import 'package:flutter/material.dart';

/// Paleta de colores central de la aplicación.
/// Regla 60/30/10: 60% neutros, 30% primario, 10% acento.
abstract final class AppColores {
  // ── Primario (30%) ──────────────────────────────────────────────────────
  static const Color primario = Color(0xFF0A1628);
  static const Color primarioSuave = Color(0xFF183A68);
  static const Color primarioDark = Color(0xFF000000);
  static const Color sobrePrimario = Colors.white;

  // ── Acento (10%) ────────────────────────────────────────────────────────
  static const Color acento = Color(0xFF0066FF);
  static const Color acentoSuave = Color(0xFF69A7FF);
  static const Color acentoAdmin = Color(0xFF1565C0);
  static const Color acentoFondo = Color(0xFFF0F4FF);
  static const Color acentoFondoFuerte = Color(0xFFDCE8FF);

  // ── Neutros (60%) ───────────────────────────────────────────────────────
  static const Color fondo = Color(0xFFF5F7FA);
  static const Color superficie = Colors.white;
  static const Color tarjeta = Colors.white;
  static const Color divisor = Color(0xFFEEEEEE);
  static const Color borde = Color(0xFFE0E0E0);
  static const Color overlay = Color(0x1A000000);
  static const Color vidrio = Color(0x1FFFFFFF);

  // ── Texto ────────────────────────────────────────────────────────────────
  static const Color textoPrimario = Color(0xFF1A1A1A);
  static const Color textoSecundario = Color(0xFF757575);
  static const Color textoTerciario = Color(0xFFBDBDBD);

  // ── Estado ───────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFB00020);
  static const Color exito = Color(0xFF4CAF50);
  static const Color advertencia = Color(0xFFFFC107);
  static const Color info = Color(0xFF2196F3);

  // ── Modo oscuro ──────────────────────────────────────────────────────────
  static const Color fondoOscuro = Color(0xFF121212);
  static const Color superficieOscura = Color(0xFF1E1E1E);
  static const Color tarjetaOscura = Color(0xFF2C2C2C);

  // ── Gradiente principal ─────────────────────────────────────────────────
  static const List<Color> gradiente = [primario, primarioDark];
  static const List<Color> gradienteHero = [
    primario,
    primarioSuave,
    acentoAdmin,
  ];

  static const LinearGradient gradientePrincipal = LinearGradient(
    colors: gradienteHero,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

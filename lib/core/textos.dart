import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colores.dart';

/// Estilos de texto consistentes con Poppins como fuente principal.
/// Todos los Text deben usar AppTextos en lugar de TextStyle inline.
abstract final class AppTextos {
  // ── Display ──────────────────────────────────────────────────────────────
  static TextStyle displayGrande([Color? color]) => GoogleFonts.poppins(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle displayMediano([Color? color]) => GoogleFonts.poppins(
    fontSize: 40,
    fontWeight: FontWeight.bold,
    color: color ?? AppColores.textoPrimario,
  );

  // ── Títulos ──────────────────────────────────────────────────────────────
  static TextStyle titulo([Color? color]) => GoogleFonts.poppins(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle titulo2([Color? color]) => GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle subtitulo([Color? color]) => GoogleFonts.poppins(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle seccion([Color? color]) => GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: color ?? AppColores.textoPrimario,
  );

  // ── Cuerpo ───────────────────────────────────────────────────────────────
  static TextStyle cuerpoGrande([Color? color]) => GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle cuerpo([Color? color]) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle cuerpoChico([Color? color]) => GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: color ?? AppColores.textoSecundario,
  );

  // ── Etiquetas ─────────────────────────────────────────────────────────────
  static TextStyle etiquetaGrande([Color? color]) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: color ?? AppColores.textoPrimario,
  );

  static TextStyle etiqueta([Color? color]) => GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: color ?? AppColores.textoSecundario,
  );

  static TextStyle etiquetaChica([Color? color]) => GoogleFonts.poppins(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: color ?? AppColores.textoTerciario,
    letterSpacing: 0.8,
  );

  // ── Botones ──────────────────────────────────────────────────────────────
  static TextStyle boton([Color? color]) => GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle botonChico([Color? color]) => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: color,
  );
}

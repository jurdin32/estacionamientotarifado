import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colores.dart';
import 'constantes.dart';

/// Tema central de la aplicación (claro y oscuro).
/// Usar Theme.of(context) en los widgets, nunca colores fijos.
abstract final class AppTema {
  // ── Tema claro ────────────────────────────────────────────────────────
  static ThemeData get claro => _construir(Brightness.light);

  // ── Tema oscuro ───────────────────────────────────────────────────────
  static ThemeData get oscuro => _construir(Brightness.dark);

  static ThemeData _construir(Brightness brightness) {
    final esDark = brightness == Brightness.dark;
    final colorFondo = esDark ? AppColores.fondoOscuro : AppColores.fondo;
    final colorSuperficie = esDark
        ? AppColores.superficieOscura
        : AppColores.superficie;
    final colorTarjeta = esDark ? AppColores.tarjetaOscura : AppColores.tarjeta;
    final colorTexto = esDark ? Colors.white : AppColores.textoPrimario;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColores.primario,
      brightness: brightness,
      primary: AppColores.primario,
      onPrimary: AppColores.sobrePrimario,
      secondary: AppColores.acento,
      tertiary: AppColores.acentoSuave,
      surface: colorSuperficie,
      error: AppColores.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorFondo,
      textTheme: GoogleFonts.poppinsTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ).apply(bodyColor: colorTexto, displayColor: colorTexto),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColores.primario,
        foregroundColor: AppColores.sobrePrimario,
        elevation: AppElevacion.ninguna,
        scrolledUnderElevation: AppElevacion.ninguna,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColores.sobrePrimario,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColores.acento,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColores.textoTerciario,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadio.lg),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          elevation: AppElevacion.mediana,
          shadowColor: AppColores.acento.withValues(alpha: 0.35),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColores.acento,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColores.acento, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: AppRadio.lg),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColores.acento,
          minimumSize: const Size(48, 48),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorSuperficie,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.borde),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.borde),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.acento, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadio.lg,
          borderSide: BorderSide(color: AppColores.error, width: 2),
        ),
        labelStyle: TextStyle(color: AppColores.textoSecundario),
        errorStyle: const TextStyle(color: AppColores.error, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        elevation: AppElevacion.tarjeta,
        color: colorTarjeta,
        shape: const RoundedRectangleBorder(borderRadius: AppRadio.lg),
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: esDark ? 0.2 : 0.08),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: esDark
            ? AppColores.superficieOscura
            : AppColores.acentoFondo,
      ),
      dividerTheme: const DividerThemeData(color: AppColores.divisor),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadio.md),
        contentTextStyle: GoogleFonts.poppins(fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadio.sm),
        backgroundColor: colorSuperficie,
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadio.lg),
        elevation: AppElevacion.dialogo,
      ),
    );
  }

  /// Compatibilidad: tema claro directo (usado en MaterialApp)
  static ThemeData get tema => claro;
}

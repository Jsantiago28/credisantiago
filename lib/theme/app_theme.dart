import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores base del Plan Maestro
class AppColors {
  static const background = Color(0xFF0D0F0E);
  static const surface = Color(0xFF17191A);

  /// Superficie un poco más clara, para cajas dentro de tarjetas.
  static const surfaceAlt = Color(0xFF212524);

  /// Borde tenue de las tarjetas.
  static const border = Color(0xFF2A2F2D);
  static const green = Color(0xFF00E676);

  /// Verde oscuro para fondos de íconos y etiquetas.
  static const greenDark = Color(0xFF0F3D26);
  static const red = Color(0xFFFF5252);
  static const redDark = Color(0xFF4A1C1E);

  /// Ámbar para lo que vence hoy (ni al día ni atrasado todavía).
  static const amber = Color(0xFFFFC857);
  static const amberDark = Color(0xFF3F3417);
  static const white = Color(0xFFFFFFFF);
  static const grey = Color(0xFF9E9E9E);
}

/// Tema OSCURO — usado en la app del prestamista (dashboard, cobros, reportes)
class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.green,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.green,
        secondary: AppColors.green,
        surface: AppColors.surface,
        error: AppColors.red,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.white,
        displayColor: AppColors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
            fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.white),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green),
          minimumSize: const Size.fromHeight(48),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerColor: AppColors.border,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: TextStyle(color: AppColors.white),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(48),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.greenDark,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((estados) => GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: estados.contains(WidgetState.selected) ? AppColors.green : AppColors.grey,
            )),
        iconTheme: WidgetStateProperty.resolveWith((estados) => IconThemeData(
              color: estados.contains(WidgetState.selected) ? AppColors.green : AppColors.grey,
            )),
      ),
    );
  }

  /// Tema CLARO — usado en el formulario público del cliente (/s/{slug})
  static ThemeData light() {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      primaryColor: const Color(0xFF1565C0),
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF1565C0),
        secondary: AppColors.green,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

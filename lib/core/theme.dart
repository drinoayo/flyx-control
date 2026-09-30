import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FlyxColors {
  static const yellow = Color(0xFFFFCB05);
  static const yellowSoft = Color(0xFFFFE275);
  static const ink = Color(0xFF0B0D10);
  static const surface = Color(0xFF13161B);
  static const surface2 = Color(0xFF191D23);
  static const line = Color(0xFF252A31);
  static const muted = Color(0xFF959DA8);
  static const success = Color(0xFF62D98B);
  static const warning = Color(0xFFF6B64D);
  static const danger = Color(0xFFFF6B6B);
  static const blue = Color(0xFF67A8FF);
}

class FlyxTheme {
  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: FlyxColors.yellow,
        secondary: FlyxColors.yellowSoft,
        surface: FlyxColors.surface,
        error: FlyxColors.danger,
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displaySmall: GoogleFonts.inter(
        fontSize: 32,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(fontSize: 15, height: 1.45),
      bodyMedium: GoogleFonts.inter(fontSize: 13.5, height: 1.45),
      labelLarge: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      scaffoldBackgroundColor: FlyxColors.ink,
      textTheme: textTheme,
      dividerColor: FlyxColors.line,
      splashFactory: InkSparkle.splashFactory,
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: FlyxColors.ink,
        indicatorColor: FlyxColors.yellow.withValues(alpha: .14),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: FlyxColors.ink,
          backgroundColor: FlyxColors.yellow,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FlyxColors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: FlyxColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FlyxColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FlyxColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FlyxColors.yellow),
        ),
      ),
    );
  }

  static ThemeData light() {
    return dark();
  }
}

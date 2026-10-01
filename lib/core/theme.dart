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

  static Color accentFor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color mutedFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color successFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? success
          : const Color(0xFF1F7A45);

  static Color warningFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? warning
          : const Color(0xFF9A5B00);

  static Color dangerFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? danger
          : const Color(0xFFB42318);

  static Color blueFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? blue
          : const Color(0xFF175CD3);
}

class FlyxTheme {
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background =
        dark ? FlyxColors.ink : const Color(0xFFF6F7F9);
    final surface =
        dark ? FlyxColors.surface : Colors.white;
    final surfaceHigh =
        dark ? const Color(0xFF171B20) : const Color(0xFFF0F2F5);
    final line =
        dark ? FlyxColors.line : const Color(0xFFDDE1E7);
    final onSurface =
        dark ? const Color(0xFFF7F8FA) : const Color(0xFF171A1F);
    final onSurfaceVariant =
        dark ? FlyxColors.muted : const Color(0xFF667085);
    final accent =
        dark ? FlyxColors.yellow : const Color(0xFF8A6800);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: dark ? FlyxColors.ink : Colors.white,
      secondary: dark ? FlyxColors.yellowSoft : const Color(0xFF9A7400),
      onSecondary: dark ? FlyxColors.ink : Colors.white,
      error: FlyxColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: onSurfaceVariant,
      outline: line,
      outlineVariant: line,
    );

    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displaySmall: GoogleFonts.inter(
        fontSize: 32,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: onSurface,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: onSurface,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        height: 1.45,
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13.5,
        height: 1.45,
        color: onSurface,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerColor: line,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: background,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : onSurfaceVariant,
            size: states.contains(WidgetState.selected) ? 27 : 25,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? accent
                : onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: FlyxColors.ink,
          backgroundColor: FlyxColors.yellow,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurfaceVariant.withValues(alpha: .45);
          }
          return states.contains(WidgetState.selected)
              ? accent
              : onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurfaceVariant.withValues(alpha: .12);
          }
          return states.contains(WidgetState.selected)
              ? accent.withValues(alpha: .28)
              : onSurfaceVariant.withValues(alpha: .18);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(
          dark ? FlyxColors.ink : Colors.white,
        ),
        side: BorderSide(color: onSurfaceVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? accent
                : onSurfaceVariant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? accent.withValues(alpha: dark ? .15 : .10)
                : Colors.transparent;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: line)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      cardColor: surface,
    );
  }
}

import 'package:flutter/material.dart';

/// Visual primitives for FundWell screens.  These tokens deliberately contain
/// no business-state meaning; financial and account rules remain in features.
abstract final class FundWellTokens {
  static const canvas = Color(0xFFF8F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFF4F1F7);
  static const outline = Color(0xFFE5DFE9);
  static const ink = Color(0xFF1D1B20);
  static const mutedInk = Color(0xFF625B68);
  static const purple = Color(0xFF704DB5);
  static const positive = Color(0xFF18794E);
  static const warning = Color(0xFFA15C00);
  static const danger = Color(0xFFB3261E);

  static const radiusSmall = 10.0;
  static const radius = 14.0;
  static const radiusLarge = 18.0;

  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
}

ThemeData fundWellTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: FundWellTokens.purple,
        brightness: Brightness.light,
        surface: FundWellTokens.surface,
      ).copyWith(
        primary: FundWellTokens.purple,
        onPrimary: Colors.white,
        surface: FundWellTokens.surface,
        onSurface: FundWellTokens.ink,
        onSurfaceVariant: FundWellTokens.mutedInk,
        outlineVariant: FundWellTokens.outline,
        error: FundWellTokens.danger,
      );
  final text = Typography.material2021().black
      .apply(bodyColor: FundWellTokens.ink, displayColor: FundWellTokens.ink)
      .copyWith(
        headlineLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: FundWellTokens.canvas,
    textTheme: text,
    dividerColor: FundWellTokens.outline,
    cardTheme: CardThemeData(
      color: FundWellTokens.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FundWellTokens.radius),
        side: const BorderSide(color: FundWellTokens.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FundWellTokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FundWellTokens.radiusSmall),
        borderSide: const BorderSide(color: FundWellTokens.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FundWellTokens.radiusSmall),
        borderSide: const BorderSide(color: FundWellTokens.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FundWellTokens.radiusSmall),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: const BorderSide(color: FundWellTokens.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FundWellTokens.radiusSmall),
        ),
      ),
    ),
  );
}

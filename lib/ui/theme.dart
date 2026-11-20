import 'package:flutter/material.dart';
import 'tokens.dart';

TextTheme _buildTextTheme(TickTokens tokens) {
  return TextTheme(
    displayMedium: TextStyle(
      fontSize: 28,
      height: 34 / 28,
      fontWeight: FontWeight.bold,
      color: tokens.text,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      color: tokens.text,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w500,
      color: tokens.text,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 22 / 16,
      fontWeight: FontWeight.normal,
      color: tokens.text,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      color: tokens.text,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.normal,
      color: tokens.textSecondary,
    ),
  );
}

ThemeData buildLightTheme() {
  const tokens = TickTokens.light;
  final textTheme = _buildTextTheme(tokens);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: tokens.bg,
    colorScheme: ColorScheme.light(
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      surface: tokens.surface,
      onSurface: tokens.text,
      error: tokens.fail,
    ),
    extensions: const [tokens],
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    dividerColor: tokens.border,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: tokens.primary.withValues(alpha: 0.15),
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      elevation: 3,
      height: 64,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.text,
      contentTextStyle: textTheme.bodyLarge?.copyWith(color: tokens.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusCard),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        minimumSize: Size(tokens.minTouchTarget, tokens.answerButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusCard),
        ),
        textStyle: textTheme.titleMedium,
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  const tokens = TickTokens.dark;
  final textTheme = _buildTextTheme(tokens);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: tokens.bg,
    colorScheme: ColorScheme.dark(
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      surface: tokens.surface,
      onSurface: tokens.text,
      error: tokens.fail,
    ),
    extensions: const [tokens],
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    dividerColor: tokens.border,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: tokens.primary.withValues(alpha: 0.25),
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      elevation: 3,
      height: 64,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tokens.surface,
      contentTextStyle: textTheme.bodyLarge?.copyWith(color: tokens.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusCard),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        minimumSize: Size(tokens.minTouchTarget, tokens.answerButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusCard),
        ),
        textStyle: textTheme.titleMedium,
      ),
    ),
  );
}

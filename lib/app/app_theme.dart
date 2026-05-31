import 'package:flutter/material.dart';

abstract final class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
}

extension AppBreakpoints on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isMobile => screenWidth < Breakpoints.mobile;
  bool get isTablet =>
      screenWidth >= Breakpoints.mobile && screenWidth < Breakpoints.tablet;
  bool get isDesktop => screenWidth >= Breakpoints.tablet;
}

abstract final class OmniGymColors {
  static const background = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D27);
  static const card = Color(0xFF1E2433);
  static const border = Color(0xFF2D3748);
  static const primary = Color(0xFF2563EB);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const success = Color(0xFF22C55E);
  static const errorRed = Color(0xFFEF4444);
}

ThemeData buildDarkTheme({Color primary = OmniGymColors.primary}) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.white,
      secondary: primary,
      onSecondary: Colors.white,
      error: OmniGymColors.errorRed,
      onError: Colors.white,
      surface: OmniGymColors.surface,
      onSurface: OmniGymColors.textPrimary,
      surfaceContainerHighest: OmniGymColors.card,
      outline: OmniGymColors.border,
      outlineVariant: OmniGymColors.border,
    ),
    scaffoldBackgroundColor: OmniGymColors.background,
    cardColor: OmniGymColors.card,
    dividerColor: OmniGymColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: OmniGymColors.surface,
      foregroundColor: OmniGymColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OmniGymColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: OmniGymColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: OmniGymColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: OmniGymColors.errorRed),
      ),
      labelStyle: const TextStyle(color: OmniGymColors.textSecondary),
      hintStyle: const TextStyle(color: OmniGymColors.textSecondary),
      prefixIconColor: OmniGymColors.textSecondary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    cardTheme: CardThemeData(
      color: OmniGymColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: OmniGymColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: OmniGymColors.textPrimary,
      iconColor: OmniGymColors.textSecondary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? primary : Colors.grey,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary.withAlpha(80)
            : OmniGymColors.border,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: OmniGymColors.card,
      contentTextStyle: const TextStyle(color: OmniGymColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: OmniGymColors.border),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: OmniGymColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: OmniGymColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OmniGymColors.card,
      side: const BorderSide(color: OmniGymColors.border),
      labelStyle: const TextStyle(color: OmniGymColors.textSecondary),
      selectedColor: primary.withAlpha(40),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OmniGymColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
  );
}

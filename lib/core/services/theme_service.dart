import 'package:flutter/material.dart';
import '../models/tenant.dart';
import '../../app/app_theme.dart';

class ThemeService {
  const ThemeService._();

  static ThemeData buildTheme({
    required Tenant? tenant,
    required Brightness brightness,
  }) {
    final primary = parseColor(
      tenant?.settings.primaryColor,
      fallback: OmniGymColors.primary,
    );
    final secondary = parseColor(
      tenant?.settings.secondaryColor,
      fallback: OmniGymColors.secondary,
    );

    final scheme = brightness == Brightness.dark
        ? OmniGymColorScheme.dark(primary: primary, secondary: secondary)
        : OmniGymColorScheme.light(primary: primary, secondary: secondary);

    return _buildThemeFromScheme(scheme);
  }

  static ThemeData _buildThemeFromScheme(OmniGymColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme.toColorScheme(),
      scaffoldBackgroundColor: scheme.background,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: scheme.onBackground),
        bodyMedium: TextStyle(color: scheme.onBackground),
        bodySmall: TextStyle(color: scheme.onSurfaceVariant),
        titleLarge: TextStyle(color: scheme.onBackground),
        titleMedium: TextStyle(color: scheme.onBackground),
        titleSmall: TextStyle(color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.border),
      dividerColor: scheme.border,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      listTileTheme: ListTileThemeData(
        textColor: scheme.onBackground,
        iconColor: scheme.onSurfaceVariant,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withAlpha(80)
              : scheme.border,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.card,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.card,
        side: BorderSide(color: scheme.border),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        selectedColor: scheme.primary.withAlpha(40),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }

  static ThemeMode resolveThemeMode(String? mode) => switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

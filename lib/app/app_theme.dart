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

/// Fallback de colores fijos. Se mantiene como respaldo interno mientras se
/// migra progresivamente al tema dinámico por tenant.
abstract final class OmniGymColors {
  static const background = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D27);
  static const card = Color(0xFF1E2433);
  static const border = Color(0xFF2D3748);
  static const primary = Color(0xFF2563EB);
  static const secondary = Color(0xFF03DAC6);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const success = Color(0xFF22C55E);
  static const errorRed = Color(0xFFEF4444);
}

/// Paleta predefinida para selección de branding en la UI.
abstract final class OmniGymPalette {
  static const List<Color> primaries = [
    Color(0xFF6750A4),
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFD32F2F),
    Color(0xFFF57C00),
    Color(0xFF00796B),
    Color(0xFF5D4037),
    Color(0xFF455A64),
  ];

  static const List<Color> secondaries = [
    Color(0xFF03DAC6),
    Color(0xFFFFAB91),
    Color(0xFF81C784),
    Color(0xFFEF9A9A),
    Color(0xFFFFCC80),
    Color(0xFF80CBC4),
    Color(0xFFBCAAA4),
    Color(0xFFB0BEC5),
  ];
}

/// Esquema de colores dinámico construido a partir de un par primario/secundario
/// seleccionado por el tenant. Expone los colores que necesita [ThemeService]
/// y genera un [ColorScheme] compatible con Material 3.
class OmniGymColorScheme {
  OmniGymColorScheme._({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.card,
    required this.onBackground,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.border,
    required this.error,
    required this.brightness,
  })  : onPrimary = _contrastFor(primary),
        onSecondary = _contrastFor(secondary),
        onError = Colors.white;

  factory OmniGymColorScheme.light({
    required Color primary,
    required Color secondary,
  }) {
    return OmniGymColorScheme._(
      primary: primary,
      secondary: secondary,
      background: const Color(0xFFF8F9FC),
      surface: Colors.white,
      card: Colors.white,
      onBackground: const Color(0xFF1A1D27),
      onSurface: const Color(0xFF1A1D27),
      onSurfaceVariant: const Color(0xFF64748B),
      border: const Color(0xFFE2E8F0),
      error: const Color(0xFFDC2626),
      brightness: Brightness.light,
    );
  }

  factory OmniGymColorScheme.dark({
    required Color primary,
    required Color secondary,
  }) {
    return OmniGymColorScheme._(
      primary: primary,
      secondary: secondary,
      background: OmniGymColors.background,
      surface: OmniGymColors.surface,
      card: OmniGymColors.card,
      onBackground: OmniGymColors.textPrimary,
      onSurface: OmniGymColors.textPrimary,
      onSurfaceVariant: OmniGymColors.textSecondary,
      border: OmniGymColors.border,
      error: OmniGymColors.errorRed,
      brightness: Brightness.dark,
    );
  }

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color error;
  final Color onError;
  final Color background;
  final Color surface;
  final Color card;
  final Color onBackground;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color border;

  ColorScheme toColorScheme() => ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        secondary: secondary,
        onSecondary: onSecondary,
        error: error,
        onError: onError,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: card,
        outline: border,
        outlineVariant: border,
      );

  static Color _contrastFor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

extension ColorHex on Color {
  String toHex() => '#${toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

Color parseColor(String? hex, {required Color fallback}) {
  if (hex == null || hex.isEmpty) return fallback;
  try {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.parse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return Color(value);
  } catch (_) {
    return fallback;
  }
}

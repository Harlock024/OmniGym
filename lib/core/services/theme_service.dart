import 'package:flutter/material.dart';
import '../models/tenant.dart';
import '../../app/app_theme.dart';

class ThemeService {
  const ThemeService._();

  static ThemeData fromSettings(TenantSettings settings) {
    final primary = _parseColor(settings.primaryColor) ?? OmniGymColors.primary;
    return buildDarkTheme(primary: primary);
  }

  static ThemeData get defaultTheme => buildDarkTheme();

  static Color? _parseColor(String hex) {
    try {
      final cleaned = hex.replaceFirst('#', '');
      final value = int.parse(
        cleaned.length == 6 ? 'FF$cleaned' : cleaned,
        radix: 16,
      );
      return Color(value);
    } catch (_) {
      return null;
    }
  }
}

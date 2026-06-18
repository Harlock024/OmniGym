import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/app/app_theme.dart';

void main() {
  group('OmniGymColors', () {
    test('primary color is defined', () {
      expect(OmniGymColors.primary, isA<Object>());
    });

    test('background, surface and card are defined', () {
      expect(OmniGymColors.background, isA<Object>());
      expect(OmniGymColors.surface, isA<Object>());
      expect(OmniGymColors.card, isA<Object>());
    });

    test('text colors are defined', () {
      expect(OmniGymColors.textPrimary, isA<Object>());
      expect(OmniGymColors.textSecondary, isA<Object>());
    });

    test('status colors are defined', () {
      expect(OmniGymColors.success, isA<Object>());
      expect(OmniGymColors.errorRed, isA<Object>());
      expect(OmniGymColors.border, isA<Object>());
    });
  });
}

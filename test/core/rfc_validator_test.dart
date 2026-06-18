import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/utils/rfc_validator.dart';

void main() {
  group('RfcValidator', () {
    test('RFC valido (SAT generico XEXX010101000)', () {
      expect(RfcValidator.isValid('XEXX010101000'), isTrue);
      expect(RfcValidator.validate('XEXX010101000'), isNull);
    });

    test('RFC persona moral valido (12 caracteres)', () {
      expect(RfcValidator.isValid('AAA010101AA1'), isTrue);
    });

    test('RFC invalidos son rechazados', () {
      expect(RfcValidator.isValid(''), isFalse);
      expect(RfcValidator.isValid('12345'), isFalse);
      expect(RfcValidator.isValid('ABCDEFGHIJKA'), isFalse);
    });

    test('RFC con formato invalido', () {
      expect(RfcValidator.isValid('XXXXX'), isFalse);
      expect(RfcValidator.isValid('ABC123456789'), isFalse);
    });

    test('RFC con digito verificador incorrecto', () {
      expect(RfcValidator.isValid('XAXX010101000'), isFalse);
      expect(RfcValidator.validate('XAXX010101000'), isNotNull);
    });

    test('validate con required retorna error para vacio', () {
      expect(
        RfcValidator.validate('', required: true),
        'El RFC es obligatorio.',
      );
    });

    test('validate permite vacio por defecto', () {
      expect(RfcValidator.validate(''), isNull);
      expect(RfcValidator.validate(null), isNull);
    });

    test('validate retorna mensaje para formato largo incorrecto', () {
      expect(
        RfcValidator.validate('ABC'),
        'El RFC debe tener 12 o 13 caracteres.',
      );
    });
  });
}

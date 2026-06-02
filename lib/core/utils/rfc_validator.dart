/// Validación de RFC del SAT: formato y dígito verificador.
///
/// El RFC tiene 12 posiciones (personas morales) o 13 (personas físicas).
/// El último carácter es el dígito verificador, calculado sobre el resto.
class RfcValidator {
  RfcValidator._();

  // Tabla oficial de valores del SAT para el cálculo del dígito verificador.
  static const String _dict = '0123456789ABCDEFGHIJKLMN&OPQRSTUVWXYZ Ñ';

  // Formato general: 3 letras (moral) o 4 (física), fecha AAMMDD y homoclave de 3.
  static final RegExp _format = RegExp(
    r'^[A-ZÑ&]{3,4}[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[A-Z0-9]{2}[0-9A]$',
  );

  /// Devuelve `null` si el RFC es válido, o un mensaje de error en caso contrario.
  /// Acepta un RFC vacío como válido (campo opcional); usa [required] para exigirlo.
  static String? validate(String? raw, {bool required = false}) {
    final rfc = (raw ?? '').trim().toUpperCase();
    if (rfc.isEmpty) {
      return required ? 'El RFC es obligatorio.' : null;
    }
    if (rfc.length != 12 && rfc.length != 13) {
      return 'El RFC debe tener 12 o 13 caracteres.';
    }
    if (!_format.hasMatch(rfc)) {
      return 'Formato de RFC inválido.';
    }
    if (!_checkDigitOk(rfc)) {
      return 'El dígito verificador del RFC no coincide.';
    }
    return null;
  }

  /// `true` si el RFC tiene formato y dígito verificador correctos.
  static bool isValid(String? raw) => validate(raw) == null && (raw ?? '').trim().isNotEmpty;

  static bool _checkDigitOk(String rfc) {
    // Cuerpo sin el dígito verificador, alineado a 12 posiciones por la izquierda.
    final body = rfc.substring(0, rfc.length - 1).padLeft(12, ' ');
    final expected = rfc[rfc.length - 1];

    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final value = _dict.indexOf(body[i]);
      if (value < 0) return false; // carácter fuera de la tabla
      sum += value * (13 - i);
    }

    final remainder = sum % 11;
    final digit = 11 - remainder;
    final String computed;
    if (digit == 11) {
      computed = '0';
    } else if (digit == 10) {
      computed = 'A';
    } else {
      computed = digit.toString();
    }
    return computed == expected;
  }
}

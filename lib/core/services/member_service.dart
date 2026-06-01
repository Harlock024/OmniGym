import 'dart:convert';

import 'package:http/http.dart' as http;

class MemberService {
  static const _workerBase = 'https://omni-gym.hadith024.workers.dev';
  static const _secret = String.fromEnvironment(
    'R2_UPLOAD_SECRET',
    defaultValue: 'omni-r2-2025-dev',
  );

  /// Crea un socio en Firebase Auth + Firestore y le envía el email de bienvenida.
  /// Devuelve uid, qrToken y la contraseña temporal para mostrársela al recepcionista.
  static Future<({String uid, String qrToken, String tempPassword})> createMember({
    required String tenantId,
    required String gymName,
    required String name,
    required String email,
    String? phone,
    required DateTime expirationDate,
    required List<String> allowedBranches,
  }) async {
    final response = await http.post(
      Uri.parse('$_workerBase/create-member'),
      headers: {
        'Authorization': 'Bearer $_secret',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'tenantId': tenantId,
        'gymName': gymName,
        'name': name,
        'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'expirationDate': expirationDate.toUtc().toIso8601String(),
        'allowedBranches': allowedBranches,
      }),
    );

    if (response.statusCode == 409) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw MemberAlreadyExistsException(
          data['error'] as String? ?? 'El correo ya está registrado.');
    }

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Error al crear el socio (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      uid: data['uid'] as String,
      qrToken: data['qrToken'] as String,
      tempPassword: data['tempPassword'] as String,
    );
  }
}

class MemberAlreadyExistsException implements Exception {
  const MemberAlreadyExistsException(this.message);
  final String message;
  @override
  String toString() => message;
}

import 'dart:convert';

import 'package:http/http.dart' as http;

class WorkerService {
  static const _base = 'https://omni-gym.hadith024.workers.dev';
  static const _secret = String.fromEnvironment(
    'R2_UPLOAD_SECRET',
    defaultValue: 'omni-r2-2025-dev',
  );

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer $_secret',
        'Content-Type': 'application/json',
      };

  /// Asigna custom claims a un usuario existente de Firebase Auth.
  static Future<void> setClaims({
    required String uid,
    required String role,
    required String tenantId,
    String? branchId,
  }) async {
    final body = <String, dynamic>{
      'uid': uid,
      'role': role,
      'tenant_id': tenantId,
    };
    if (branchId != null) body['branch_id'] = branchId;

    final res = await http.post(
      Uri.parse('$_base/set-claims'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception('set-claims failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Crea un usuario en Firebase Auth, asigna claims y envía email de contraseña.
  /// Devuelve el UID del nuevo usuario.
  static Future<String> createStaff({
    required String name,
    required String email,
    required String role,
    required String tenantId,
    String? branchId,
    String? gymName,
    String? csdCargo,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'role': role,
      'tenant_id': tenantId,
    };
    if (branchId != null) body['branch_id'] = branchId;
    if (gymName != null && gymName.isNotEmpty) body['gymName'] = gymName;
    if (csdCargo != null && csdCargo.isNotEmpty) body['csd_cargo'] = csdCargo;

    final res = await http.post(
      Uri.parse('$_base/create-staff'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (res.statusCode == 409) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw StaffAlreadyExistsException(
          data['error'] as String? ?? 'El correo ya está registrado.');
    }

    if (res.statusCode != 200) {
      throw Exception('create-staff failed (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['uid'] as String;
  }

  /// Consulta el catálogo postal SEPOMEX (Cloudflare D1) por código postal.
  /// Devuelve null si el CP no existe o falla la consulta (el catálogo es ayuda,
  /// no debe bloquear el formulario).
  static Future<PostalLookup?> lookupPostalCode(String cp) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/catalogs/postal?cp=$cp'),
        headers: _headers,
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['found'] != true) return null;
      return PostalLookup(
        estado: data['estado'] as String?,
        municipio: data['municipio'] as String?,
        ciudad: data['ciudad'] as String?,
        colonias: (data['colonias'] as List<dynamic>? ?? [])
            .map((c) => (c as Map<String, dynamic>)['nombre'] as String)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Elimina un operador: borra su cuenta de Firebase Auth y el doc /users/{uid}.
  static Future<void> deleteStaff(String uid) async {
    final res = await http.post(
      Uri.parse('$_base/delete-staff'),
      headers: _headers,
      body: jsonEncode({'uid': uid}),
    );
    if (res.statusCode != 200) {
      throw Exception('delete-staff failed (${res.statusCode}): ${res.body}');
    }
  }
}

class PostalLookup {
  const PostalLookup({
    this.estado,
    this.municipio,
    this.ciudad,
    this.colonias = const [],
  });
  final String? estado;
  final String? municipio;
  final String? ciudad;
  final List<String> colonias;
}

class StaffAlreadyExistsException implements Exception {
  const StaffAlreadyExistsException(this.message);
  final String message;
  @override
  String toString() => message;
}

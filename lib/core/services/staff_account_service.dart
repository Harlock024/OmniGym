import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'worker_auth.dart';

final staffAccountServiceProvider = Provider<StaffAccountService>((ref) {
  final service = StaffAccountService();
  ref.onDispose(service.close);
  return service;
});

class StaffAccountException implements Exception {
  const StaffAccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

class StaffAccountResult {
  const StaffAccountResult({
    required this.uid,
    required this.username,
    required this.emailSent,
  });
  final String uid;
  final String username;
  final bool emailSent;
}

class StaffInvitation {
  const StaffInvitation({
    required this.name,
    required this.username,
    required this.gymName,
    required this.branchName,
    required this.role,
  });
  final String name;
  final String username;
  final String gymName;
  final String branchName;
  final String role;
}

class StaffAccountService {
  static const _unavailableMessage =
      'El servicio de cuentas laborales todavía no está disponible en este servidor. '
      'Contacta al administrador para actualizarlo.';

  StaffAccountService({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'WORKER_BASE_URL',
      defaultValue: 'https://omni-gym.hadith024.workers.dev',
    ),
    Future<Map<String, String>> Function()? authHeaders,
  }) : _client = client ?? http.Client(),
       _authHeaders = authHeaders ?? workerHeaders;

  final http.Client _client;
  final String baseUrl;
  final Future<Map<String, String>> Function() _authHeaders;
  void close() => _client.close();

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
    String? idToken,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) headers.addAll(await _authHeaders());
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      if (response.statusCode == 404) {
        throw const StaffAccountException(_unavailableMessage);
      }
      throw const StaffAccountException(
        'No se pudo conectar con el servicio. Intenta más tarde.',
      );
    }
    if (response.statusCode == 404 &&
        const {
          '',
          'not found',
          'not_found',
        }.contains((data['error'] as String? ?? '').trim().toLowerCase())) {
      throw const StaffAccountException(_unavailableMessage);
    }
    if (response.statusCode != 200) {
      throw StaffAccountException(
        data['error'] as String? ?? 'No se pudo completar la operación.',
      );
    }
    return data;
  }

  Future<StaffAccountResult> create({
    required String name,
    required String contactEmail,
    required String role,
    required String tenantId,
    required String branchId,
    String? csdCargo,
  }) async {
    final data = await _post('/staff-accounts', {
      'name': name,
      'email': contactEmail,
      'role': role,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'csd_cargo': csdCargo,
    }, authenticated: true);
    return StaffAccountResult(
      uid: data['uid'] as String,
      username: data['username'] as String,
      emailSent: data['email_sent'] == true,
    );
  }

  Future<StaffInvitation> preview(String id, String token) async {
    final data = await _post('/staff-invitations/preview', {
      'id': id,
      'token': token,
    });
    return StaffInvitation(
      name: data['name'] as String,
      username: data['username'] as String,
      gymName: data['gym_name'] as String,
      branchName: data['branch_name'] as String,
      role: data['role'] as String,
    );
  }

  Future<void> accept(String id, String token, String idToken) async {
    await _post('/staff-invitations/accept', {
      'id': id,
      'token': token,
    }, idToken: idToken);
  }

  Future<void> reject(String id, String token) async {
    await _post('/staff-invitations/reject', {'id': id, 'token': token});
  }

  Future<bool> resend(String uid) async =>
      (await _post('/staff-invitations/resend', {
        'uid': uid,
      }, authenticated: true))['email_sent'] ==
      true;

  Future<void> deactivate(String uid) async {
    await _post('/staff-accounts/deactivate', {
      'uid': uid,
    }, authenticated: true);
  }

  Future<void> recover(String username) async {
    await _post('/staff-password-recovery', {
      'username': username.trim().toLowerCase(),
    });
  }
}

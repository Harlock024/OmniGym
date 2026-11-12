import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/core/services/login_identity.dart';
import 'package:omnigym/core/services/staff_account_service.dart';
import 'package:omnigym/features/auth/forgot_password_screen.dart';
import 'package:omnigym/features/auth/login_screen.dart';
import 'package:omnigym/features/auth/staff_invitation_screen.dart';
import 'package:omnigym/features/auth/staff_reset_password_screen.dart';

class _User extends Fake implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'recipient-id-token';
}

class _Credential extends Fake implements UserCredential {
  @override
  User get user => _User();
}

class _Auth extends Fake implements FirebaseAuth {
  String? email;
  String? deliveryEmail;
  int passwordResets = 0;
  int signIns = 0;
  String resetEmail = 'gym.ana.123@staff.omnigym.invalid';

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    if (passwordResets > 0) {
      throw FirebaseAuthException(code: 'invalid-action-code');
    }
    return resetEmail;
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    passwordResets++;
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    this.email = email;
    signIns++;
    return _Credential();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    deliveryEmail = email;
  }
}

const _details = {
  'name': 'Ana',
  'username': 'gym.ana.123',
  'gym_name': 'Gym Centro',
  'branch_name': 'Centro',
  'role': 'receptionist',
};

Future<void> _mount(
  WidgetTester tester,
  Widget screen,
  _Auth auth,
  StaffAccountService service,
) async {
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, _) => screen),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('Acceso configurado')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(service.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        staffAccountServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _passwords(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Employee123!');
  await tester.enterText(find.byType(TextFormField).at(1), 'Employee123!');
  tester.testTextInput.hide();
}

void main() {
  test('existing email logins and normalized work usernames keep separate identities', () {
    expect(
      LoginIdentity.emailFor(' Owner@Example.test '),
      'owner@example.test',
    );
    expect(
      LoginIdentity.emailFor(' GYM.ANA.123 '),
      'gym.ana.123@staff.omnigym.invalid',
    );
    expect(LoginIdentity.isUsername('gym.ana.123'), isTrue);
    expect(LoginIdentity.isUsername('contact@example.test'), isFalse);
  });

  test('creation authenticates the inviter and reports delivery failure without claiming success', () async {
    final service = StaffAccountService(
      authHeaders: () async => {'Authorization': 'Bearer owner'},
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer owner');
        expect(request.url.path, '/staff-accounts');
        final body = jsonDecode(request.body) as Map;
        expect(body['email'], 'contact@example.test');
        expect(body.containsKey('password'), isFalse);
        return http.Response(
          jsonEncode({
            'uid': 'work',
            'username': 'gym.ana.123',
            'email_sent': false,
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    final result = await service.create(
      name: 'Ana',
      contactEmail: 'contact@example.test',
      role: 'receptionist',
      tenantId: 'gym',
      branchId: 'b',
    );
    expect(result.username, 'gym.ana.123');
    expect(result.emailSent, isFalse);
  });

  testWidgets(
    'login accepts a generated username and preserves existing email access',
    (tester) async {
      final auth = _Auth();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [firebaseAuthProvider.overrideWithValue(auth)],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'gym.ana.123');
      await tester.enterText(find.byType(TextFormField).at(1), 'Employee123!');
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(auth.email, LoginIdentity.emailFor('gym.ana.123'));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'owner@example.test',
      );
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(auth.email, 'owner@example.test');
    },
  );

  testWidgets(
    'invitation activation authenticates the recipient and can resume after a failed response',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      int accepts = 0;
      final service = StaffAccountService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/preview')) {
            return http.Response(jsonEncode(_details), 200);
          }
          expect(request.url.path, '/staff-invitations/accept');
          expect(request.headers['Authorization'], 'Bearer recipient-id-token');
          expect(jsonDecode(request.body), {'id': 'work', 'token': 'secret'});
          accepts++;
          return accepts == 1
              ? http.Response('{"error":"Intenta de nuevo"}', 503)
              : http.Response('{"ok":true}', 200);
        }),
      );
      await _mount(
        tester,
        const StaffInvitationScreen(
          id: 'work',
          token: 'secret',
          code: 'firebase-code',
        ),
        auth,
        service,
      );
      expect(find.textContaining('Gym Centro'), findsOneWidget);
      await _passwords(tester);
      await tester.ensureVisible(find.text('Aceptar y activar cuenta'));
      await tester.tap(find.text('Aceptar y activar cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Intenta de nuevo'), findsOneWidget);
      await tester.ensureVisible(find.text('Aceptar y activar cuenta'));
      await tester.tap(find.text('Aceptar y activar cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Acceso configurado'), findsOneWidget);
      expect(auth.passwordResets, 1);
      expect(auth.signIns, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejecting an invitation does not change password or sign in', (
    tester,
  ) async {
    final auth = _Auth();
    final paths = <String>[];
    final service = StaffAccountService(
      client: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/preview') ? _details : {'ok': true},
          ),
          200,
        );
      }),
    );
    await _mount(
      tester,
      const StaffInvitationScreen(id: 'work', token: 'secret', code: 'code'),
      auth,
      service,
    );
    await tester.ensureVisible(find.text('Rechazar invitación'));
    await tester.tap(find.text('Rechazar invitación'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invitación rechazada'), findsOneWidget);
    expect(paths.last, '/staff-invitations/reject');
    expect(auth.passwordResets, 0);
    expect(auth.signIns, 0);
  });

  testWidgets('a mismatched password code cannot reset another account', (
    tester,
  ) async {
    final auth = _Auth()..resetEmail = 'personal@example.test';
    final service = StaffAccountService(
      client: MockClient((request) async {
        expect(request.url.path, '/staff-invitations/preview');
        return http.Response(jsonEncode(_details), 200);
      }),
    );
    await _mount(
      tester,
      const StaffInvitationScreen(id: 'work', token: 'secret', code: 'code'),
      auth,
      service,
    );
    await _passwords(tester);
    await tester.ensureVisible(find.text('Aceptar y activar cuenta'));
    await tester.tap(find.text('Aceptar y activar cuenta'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('no corresponde a esta invitación'),
      findsOneWidget,
    );
    expect(auth.passwordResets, 0);
    expect(auth.signIns, 0);
  });

  testWidgets(
    'expired invitations display the server message without offering activation',
    (tester) async {
      final service = StaffAccountService(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"La invitación venció. Solicita un reenvío al gimnasio."}',
            410,
          ),
        ),
      );
      await _mount(
        tester,
        const StaffInvitationScreen(id: 'work', token: 'secret', code: 'code'),
        _Auth(),
        service,
      );
      expect(find.textContaining('La invitación venció.'), findsOneWidget);
      expect(find.text('Aceptar y activar cuenta'), findsNothing);
    },
  );

  testWidgets(
    'work recovery uses the contact-delivery endpoint rather than a nonexistent mailbox',
    (tester) async {
      final auth = _Auth();
      bool requested = false;
      final service = StaffAccountService(
        client: MockClient((request) async {
          expect(request.url.path, '/staff-password-recovery');
          expect(jsonDecode(request.body), {'username': 'gym.ana.123'});
          expect(request.headers.containsKey('Authorization'), isFalse);
          requested = true;
          return http.Response('{"ok":true}', 200);
        }),
      );
      await _mount(tester, const ForgotPasswordScreen(), auth, service);
      await tester.enterText(find.byType(TextFormField), 'GYM.ANA.123');
      await tester.ensureVisible(find.text('Enviar correo de recuperación'));
      await tester.tap(find.text('Enviar correo de recuperación'));
      await tester.pumpAndSettle();
      expect(requested, isTrue);
      expect(auth.deliveryEmail, isNull);
      expect(find.textContaining('correo de contacto'), findsOneWidget);
    },
  );

  testWidgets(
    'the recovery link sets a new password without logging into another account',
    (tester) async {
      final auth = _Auth();
      await _mount(
        tester,
        const StaffResetPasswordScreen(code: 'recovery-code'),
        auth,
        StaffAccountService(
          client: MockClient(
            (_) async => throw StateError('Unexpected API request'),
          ),
        ),
      );
      await _passwords(tester);
      await tester.ensureVisible(find.text('Guardar contraseña'));
      await tester.tap(find.text('Guardar contraseña'));
      await tester.pumpAndSettle();
      expect(find.text('Contraseña actualizada'), findsOneWidget);
      expect(auth.passwordResets, 1);
      expect(auth.signIns, 0);
    },
  );
}

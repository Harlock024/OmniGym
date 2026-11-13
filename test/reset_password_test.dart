import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/app/router.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/features/auth/reset_password_screen.dart';

class _Auth extends Fake implements FirebaseAuth {
  String? verificationError;
  String? confirmationError;
  int verifies = 0;
  int resets = 0;

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    verifies++;
    if (verificationError != null) {
      throw FirebaseAuthException(code: verificationError!);
    }
    return 'socio@example.test';
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    resets++;
    if (confirmationError != null) {
      throw FirebaseAuthException(code: confirmationError!);
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Auth auth, {
  String code = 'code',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [firebaseAuthProvider.overrideWithValue(auth)],
      child: MaterialApp(home: ResetPasswordScreen(code: code)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Guardar contraseña'));
  await tester.tap(find.text('Guardar contraseña'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('missing and expired codes cannot submit a password', (
    tester,
  ) async {
    final auth = _Auth();
    await _mount(tester, auth, code: '');
    expect(auth.verifies, 0);
    expect(find.text('Solicitar otro enlace'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    auth.verificationError = 'expired-action-code';
    await _mount(tester, auth, code: 'expired');
    expect(auth.verifies, 1);
    expect(find.text('Solicitar otro enlace'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(auth.resets, 0);
  });

  testWidgets('verification can recover after a connection failure', (
    tester,
  ) async {
    final auth = _Auth()..verificationError = 'network-request-failed';
    await _mount(tester, auth);
    expect(find.text('Reintentar'), findsOneWidget);
    auth.verificationError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(auth.verifies, 2);
    expect(find.textContaining('socio@example.test'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets(
    'validates confirmation and handles a code expiring during submission',
    (tester) async {
      final auth = _Auth()..confirmationError = 'invalid-action-code';
      await _mount(tester, auth);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'password123');
      await tester.enterText(fields.last, 'different');
      await _save(tester);
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      expect(auth.resets, 0);
      await tester.enterText(fields.last, 'password123');
      await _save(tester);
      expect(auth.resets, 1);
      expect(find.text('Solicitar otro enlace'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  for (final path in ['/reset-password', '/staff-reset-password']) {
    testWidgets('$path remains public for email recovery links', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          currentAppUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      router.go(path);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, path);
      expect(find.text('Recuperar contraseña'), findsOneWidget);
    });
  }
}

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/app/router.dart';
import 'package:omnigym/core/models/app_user.dart';
import 'package:omnigym/core/providers/providers.dart';

import 'core/module_access_test.dart' show operatorUser;

class _SignedInUser extends Fake implements User {
  @override
  String get uid => 'reception';
}

void main() {
  testWidgets(
    'direct routes are blocked, and permission changes redirect the open page live',
    (tester) async {
      final profiles = StreamController<AppUser?>();
      final user = operatorUser('reception', UserRole.receptionist);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_SignedInUser()),
          ),
          currentAppUserProvider.overrideWith((ref) => profiles.stream),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(profiles.close);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      profiles.add(user);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/no-access');
      expect(
        find.textContaining('Aún no tienes módulos asignados.'),
        findsOneWidget,
      );
      router.go('/facturacion');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/no-access');
      profiles.add(user.copyWith(permissions: {'members': true}));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/members');
      router.go('/staff');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/members');
      profiles.add(user);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/no-access');
    },
  );
}

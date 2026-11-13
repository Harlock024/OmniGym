import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnigym/app/router.dart';
import 'package:omnigym/core/models/app_user.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/core/services/staff_account_service.dart';

import 'core/module_access_test.dart' show operatorUser;

class _SignedInUser extends Fake implements User {
  @override
  String get uid => 'reception';
}

void main() {
  testWidgets(
    'pending work accounts cannot enter gym modules or profile before acceptance',
    (tester) async {
      final profiles = StreamController<AppUser?>();
      final pending = operatorUser('reception', UserRole.receptionist).copyWith(
        status: UserStatus.pending,
        accountType: 'managed_staff',
        invitationStatus: 'pending',
        permissions: {'members': true},
      );
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
      profiles.add(pending);
      await tester.pumpAndSettle();
      for (final path in ['/members', '/profile', '/staff', '/settings']) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/access-pending',
        );
      }
      expect(find.textContaining('pendiente de activación'), findsOneWidget);
      profiles.add(
        pending.copyWith(
          status: UserStatus.active,
          invitationStatus: 'accepted',
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/members');
    },
  );

  testWidgets(
    'invitation email links stay open when another account is already signed in',
    (tester) async {
      final service = StaffAccountService(
        client: MockClient(
          (request) async => http.Response(
            '{"name":"Ana","username":"gym.ana.123","gym_name":"Gym Centro","branch_name":"Centro","role":"receptionist"}',
            200,
          ),
        ),
      );
      addTearDown(service.close);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_SignedInUser()),
          ),
          currentAppUserProvider.overrideWith(
            (ref) => Stream.value(operatorUser('owner', UserRole.owner)),
          ),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          staffAccountServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      router.go('/staff-invitation?id=work&token=secret&oobCode=code');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/staff-invitation',
      );
      expect(find.text('Invitación a Gym Centro'), findsOneWidget);
    },
  );

  for (final role in [
    UserRole.owner,
    UserRole.staff,
    UserRole.receptionist,
    UserRole.superuser,
  ]) {
    testWidgets('QR and kiosk routes stay blocked for ${role.name}', (
      tester,
    ) async {
      if (role == UserRole.owner) {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final profile = operatorUser(
        'operator',
        role,
        permissions: {'scanner': true},
      );
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_SignedInUser()),
          ),
          currentAppUserProvider.overrideWith((ref) => Stream.value(profile)),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      for (final path in ['/scanner', '/kiosk']) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, switch (role) {
          UserRole.owner => '/dashboard/owner',
          UserRole.staff => '/staff',
          UserRole.superuser => '/superadmin',
          _ => '/no-access',
        });
      }
      expect(find.byTooltip('Escáner'), findsNothing);
      expect(find.byTooltip('Modo kiosko'), findsNothing);
      expect(find.text('Escáner QR'), findsNothing);
      if (role == UserRole.owner) {
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        expect(find.text('Escáner QR'), findsNothing);
        expect(find.text('Modo kiosko'), findsNothing);
        Navigator.of(tester.element(find.text('Equipo'))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Menú'));
        await tester.pumpAndSettle();
        expect(find.text('Escáner QR'), findsNothing);
      }
    });
  }

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

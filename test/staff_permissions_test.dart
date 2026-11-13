import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/app_user.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/core/repositories/user_repository.dart';
import 'package:omnigym/features/staff/module_permissions_popover.dart';

import 'core/module_access_test.dart' show operatorUser;

void main() {
  testWidgets(
    'popover cancels locally, saves full-module grants, and fits a phone',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      final target = operatorUser('reception', UserRole.receptionist);
      await db.collection('users').doc(target.id).set({
        'name': target.name,
        'permissions': <String, bool>{},
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppUserProvider.overrideWith(
              (ref) => Stream.value(operatorUser('owner', UserRole.owner)),
            ),
            userRepositoryProvider.overrideWithValue(UserRepository(db)),
          ],
          child: MaterialApp(
            home: Scaffold(body: ModulePermissionsButton(user: target)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Permisos de reception'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(7));
      await tester.tap(find.text('Socios'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        (await db.collection('users').doc(target.id).get())
            .data()!['permissions'],
        isEmpty,
      );
      await tester.tap(find.byTooltip('Permisos de reception'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Socios'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final permissions =
          (await db.collection('users').doc(target.id).get())
                  .data()!['permissions']
              as Map;
      expect(permissions['members'], isTrue);
      expect(permissions['billing'], isFalse);
    },
  );

  testWidgets('staff cannot select modules it does not have', (tester) async {
    final actor = operatorUser(
      'staff',
      UserRole.staff,
      permissions: {'scanner': true, 'members': true},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppUserProvider.overrideWith((ref) => Stream.value(actor)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ModulePermissionsButton(
              user: operatorUser('r', UserRole.receptionist),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Permisos de r'));
    await tester.pumpAndSettle();
    final billing = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Facturación'),
    );
    final scanner = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Escáner QR'),
    );
    expect(billing.onChanged, isNull);
    expect(scanner.onChanged, isNull);
    final members = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Socios'),
    );
    expect(members.onChanged, isNotNull);
    expect(find.text('Temporalmente deshabilitado'), findsOneWidget);
  });
}

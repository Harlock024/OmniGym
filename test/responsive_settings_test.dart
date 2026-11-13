import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/tenant.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/features/superadmin/tenant_detail_screen.dart';

void main() {
  for (final owner in [true, false]) {
    for (final width in [320.0, 768.0, 1280.0]) {
      testWidgets(
        'settings tabs fit $width for ${owner ? 'Owner' : 'Superuser'}',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = FakeFirebaseFirestore();
          final tenant = Tenant(
            id: 'gym',
            slug: 'gym',
            name: 'Gimnasio con un nombre de empresa muy largo para comprobar su distribución',
            subscriptionStatus: SubscriptionStatus.active,
            billingCycleEnd: DateTime(2030),
            settings: const TenantSettings(
              country: 'MX',
              state: 'Ciudad de México',
              municipality: 'Cuauhtémoc',
              regimenFiscal: '601',
              certCerName: 'certificado-con-un-nombre-largo.cer',
              certCerUrl: 'https://example.test/cert.cer',
              certKeyName: 'llave-con-un-nombre-largo.key',
              certKeyUrl: 'https://example.test/cert.key',
            ),
          );
          await db.collection('tenants').doc('gym').set({
            ...tenant.toJson()..remove('id'),
            'settings': tenant.settings.toJson(),
          });
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                firestoreProvider.overrideWithValue(db),
                activeTenantIdFutureProvider.overrideWith((ref) async => 'gym'),
              ],
              child: MaterialApp(
                home: TenantDetailScreen(tenantId: 'gym', isOwnerMode: owner),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
          for (var index = 0; index < tabs.length; index++) {
            tabs.animateTo(index);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Tab $index at $width',
            );
            expect(find.text('Guardar cambios'), findsOneWidget);
          }
        },
      );
    }
  }
}

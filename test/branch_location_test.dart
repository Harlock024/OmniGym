import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/branch.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/features/branches/branch_location.dart';
import 'package:omnigym/features/branches/branches_screen.dart';

const branch = Branch(
  id: 'centro',
  tenantId: 'gym',
  name: 'Centro',
  isActive: true,
);
const address = BranchAddress(
  street: 'Av. Reforma 12',
  city: 'Ciudad de México',
  state: 'Ciudad de México',
  postalCode: '06000',
);

void main() {
  test('coordinates take priority and zero coordinates are valid', () {
    final url = branchLocationUrl(
      branch.copyWith(
        address: address,
        location: const BranchLocation(latitude: 0, longitude: -99.13),
      ),
    )!;
    expect(url.host, 'www.google.com');
    expect(url.path, '/maps/search/');
    expect(url.queryParameters, {'api': '1', 'query': '0.0,-99.13'});
  });

  test(
    'address is encoded and used when coordinates are missing or invalid',
    () {
      for (final location in [
        null,
        const BranchLocation(latitude: 100, longitude: 0),
      ]) {
        final url = branchLocationUrl(
          branch.copyWith(address: address, location: location),
        )!;
        expect(url.queryParameters['query'], contains('Av. Reforma 12'));
        expect(url.queryParameters['query'], contains('Ciudad de México'));
        expect(url.queryParameters['query'], contains('06000'));
      }
      expect(branchLocationUrl(branch), isNull);
    },
  );

  testWidgets(
    'branch card opens share dialog and copies its Maps link on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final db = FakeFirebaseFirestore();
      await db.collection('tenants/gym/branches').doc('centro').set({
        ...branch.toJson(),
        'address': address.toJson(),
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(db),
            activeTenantIdFutureProvider.overrideWith((ref) async => 'gym'),
          ],
          child: const MaterialApp(home: BranchesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Compartir ubicación'));
      await tester.pumpAndSettle();
      expect(find.text('Ubicación de Centro'), findsOneWidget);
      await tester.tap(find.text('Copiar enlace'));
      await tester.pumpAndSettle();
      expect(
        copied,
        branchLocationUrl(branch.copyWith(address: address)).toString(),
      );
      expect(find.text('Enlace copiado.'), findsOneWidget);
    },
  );

  testWidgets('sharing hands the branch name and Maps URL to the device', (
    tester,
  ) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    Map<Object?, Object?>? shared;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      shared = call.arguments as Map<Object?, Object?>;
      return 'app';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final located = branch.copyWith(address: address);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BranchLocationDialog(branch: located)),
      ),
    );
    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();
    expect(shared?['text'], 'Centro\n${branchLocationUrl(located)}');
    expect(shared?['originWidth'], greaterThan(0));
  });

  testWidgets('missing location offers an explanation without share actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BranchLocationDialog(branch: branch)),
      ),
    );
    expect(find.textContaining('Agrega una dirección'), findsOneWidget);
    expect(find.text('Compartir'), findsNothing);
  });
}

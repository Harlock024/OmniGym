import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/tenant.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/core/repositories/tenant_repository.dart';
import 'package:omnigym/core/services/worker_service.dart';
import 'package:omnigym/features/superadmin/superadmin_providers.dart';
import 'package:omnigym/features/superadmin/tenant_detail_screen.dart';

class _TenantRepository extends Fake implements TenantRepository {
  _TenantRepository(this.tenant);
  final Future<Tenant?> tenant;

  @override
  Future<Tenant?> get(String tenantId) => tenant;
}

final _tenant = Tenant(
  id: 'gym',
  slug: 'gym',
  name: 'Mi gimnasio',
  subscriptionStatus: SubscriptionStatus.active,
  billingCycleEnd: DateTime(2030),
  settings: const TenantSettings(
    postalCode: '93400',
    state: 'Veracruz',
    municipality: 'Papantla',
    colonia: 'Centro',
    address: 'Calle principal 10',
  ),
);

const _address = PostalLookup(
  estado: 'Veracruz de Ignacio de la Llave',
  municipio: 'Papantla',
  colonias: ['Centro', 'Otra colonia'],
);

Finder _loading(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder _dropdown(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == label,
);

bool _canSave(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Guardar cambios'),
  );
  return button.onPressed != null;
}

Future<void> _mount(
  WidgetTester tester, {
  required Future<Tenant?> tenant,
  required Future<PostalLookup?> Function(String) lookup,
  bool owner = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        activeTenantIdFutureProvider.overrideWith((ref) async => 'gym'),
        tenantRepositoryProvider.overrideWithValue(_TenantRepository(tenant)),
        postalCodeLookupProvider.overrideWithValue(lookup),
      ],
      child: MaterialApp(
        home: TenantDetailScreen(
          tenantId: owner ? null : 'gym',
          isOwnerMode: owner,
        ),
      ),
    ),
  );
}

void main() {
  for (final owner in [true, false]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets(
        'address skeleton covers delayed data at $width for owner=$owner',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final tenant = Completer<Tenant?>();
          final postal = Completer<PostalLookup?>();
          await _mount(
            tester,
            tenant: tenant.future,
            lookup: (_) => postal.future,
            owner: owner,
          );
          expect(_loading('Cargando configuración'), findsOneWidget);
          expect(_canSave(tester), isFalse);
          tenant.complete(_tenant);
          await tester.pump();
          await tester.pump();
          expect(_loading('Cargando dirección'), findsOneWidget);
          expect(_dropdown('Estado'), findsNothing);
          expect(_dropdown('Municipio'), findsNothing);
          expect(
            find.text('Revisa o completa la dirección manualmente.'),
            findsNothing,
          );
          expect(_canSave(tester), isFalse);
          final streetY = tester.getTopLeft(_field('Calle y número')).dy;
          await tester.pump(const Duration(seconds: 1));
          postal.complete(_address);
          await tester.pumpAndSettle();
          expect(_loading('Cargando dirección'), findsNothing);
          expect(
            tester
                .widget<DropdownButtonFormField<String>>(_dropdown('Estado'))
                .initialValue,
            _address.estado,
          );
          expect(
            tester
                .widget<DropdownButtonFormField<String>>(_dropdown('Municipio'))
                .initialValue,
            'Papantla',
          );
          expect(
            tester
                .widget<DropdownButtonFormField<String>>(_dropdown('Colonia'))
                .initialValue,
            'Centro',
          );
          expect(
            tester.getTopLeft(_field('Calle y número')).dy,
            closeTo(streetY, 1),
          );
          expect(_canSave(tester), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final outcome in ['not-found', 'error', 'timeout']) {
    testWidgets(
      'postal $outcome releases the skeleton and keeps the saved address',
      (tester) async {
        final postal = Completer<PostalLookup?>();
        await _mount(
          tester,
          tenant: Future.value(_tenant),
          lookup: (_) => postal.future,
        );
        await tester.pump();
        expect(_loading('Cargando dirección'), findsOneWidget);
        if (outcome == 'not-found') {
          postal.complete(null);
        } else if (outcome == 'error') {
          postal.completeError(StateError('Connection failed'));
        } else {
          await tester.pump(const Duration(seconds: 11));
        }
        await tester.pumpAndSettle();
        expect(_loading('Cargando dirección'), findsNothing);
        expect(
          find.text('Revisa o completa la dirección manualmente.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(_dropdown('Estado'))
              .initialValue,
          'Veracruz',
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(_dropdown('Municipio'))
              .initialValue,
          'Papantla',
        );
        expect(
          tester.widget<TextField>(_field('Colonia')).controller!.text,
          'Centro',
        );
        expect(_canSave(tester), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final oldFirst in [true, false]) {
    testWidgets('postal responses stay consistent with oldFirst=$oldFirst', (
      tester,
    ) async {
      final old = Completer<PostalLookup?>();
      final latest = Completer<PostalLookup?>();
      await _mount(
        tester,
        tenant: Future.value(_tenant),
        lookup: (cp) => cp == '93400' ? old.future : latest.future,
      );
      await tester.pump();
      await tester.enterText(_field('Código postal'), '06000');
      await tester.pump();
      if (oldFirst) {
        old.complete(_address);
        await tester.pump();
        await tester.pump();
        expect(_loading('Cargando dirección'), findsOneWidget);
        expect(_canSave(tester), isFalse);
      }
      latest.complete(
        const PostalLookup(
          estado: 'Ciudad de México',
          municipio: 'Cuauhtémoc',
          colonias: ['Centro nuevo'],
        ),
      );
      await tester.pumpAndSettle();
      if (!oldFirst) {
        old.complete(_address);
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<TextField>(_field('Código postal')).controller!.text,
        '06000',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(_dropdown('Estado'))
            .initialValue,
        'Ciudad de México',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(_dropdown('Colonia'))
            .initialValue,
        'Centro nuevo',
      );
      expect(_canSave(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'incomplete code cancels the loading state and ignores its pending result',
    (tester) async {
      final postal = Completer<PostalLookup?>();
      await _mount(
        tester,
        tenant: Future.value(_tenant),
        lookup: (_) => postal.future,
      );
      await tester.pump();
      await tester.enterText(_field('Código postal'), '9340');
      await tester.pump();
      expect(_loading('Cargando dirección'), findsNothing);
      expect(_canSave(tester), isTrue);
      postal.complete(_address);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(_dropdown('Estado'))
            .initialValue,
        'Veracruz',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial loading errors release the settings skeleton', (
    tester,
  ) async {
    final tenant = Completer<Tenant?>();
    await _mount(tester, tenant: tenant.future, lookup: (_) async => null);
    tenant.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(_loading('Cargando configuración'), findsNothing);
    expect(
      find.textContaining('No se pudo cargar la configuración'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

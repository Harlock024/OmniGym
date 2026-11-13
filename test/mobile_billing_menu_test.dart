import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/app/app_shell.dart';
import 'package:omnigym/core/providers/providers.dart';
import 'package:omnigym/features/facturacion/facturacion_screen.dart';

void main() {
  for (final state in [
    'loading',
    'error',
    'missing tenant',
    'empty invoices',
  ]) {
    testWidgets('billing opens the outer mobile drawer with $state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scaffold = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeTenantIdFutureProvider.overrideWith((ref) {
              return switch (state) {
                'loading' => Completer<String?>().future,
                'error' => Future<String?>.error(
                  StateError('Connection failed'),
                ),
                'missing tenant' => Future<String?>.value(null),
                _ => Future<String?>.value('gym'),
              };
            }),
            tenantFacturasProvider('gym')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: ShellScope(
              openDrawer: () => scaffold.currentState!.openDrawer(),
              child: Scaffold(
                key: scaffold,
                drawer: const Drawer(child: Text('Navegación del gimnasio')),
                body: const FacturacionScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byTooltip('Menú'), findsOneWidget);
      await tester.tap(find.byTooltip('Menú'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Navegación del gimnasio'), findsOneWidget);
      expect(scaffold.currentState!.isDrawerOpen, isTrue);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/providers.dart';
import '../core/services/theme_service.dart';
import 'router.dart';

class OmniGymApp extends ConsumerWidget {
  const OmniGymApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final tenant = ref.watch(currentTenantProvider).valueOrNull;

    return MaterialApp.router(
      title: 'OmniGym',
      debugShowCheckedModeBanner: false,
      theme: ThemeService.buildTheme(
        tenant: tenant,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeService.buildTheme(
        tenant: tenant,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeService.resolveThemeMode(tenant?.settings.themeMode),
      routerConfig: router,
    );
  }
}

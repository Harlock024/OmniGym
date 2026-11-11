import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';

class NoModulesScreen extends ConsumerWidget {
  const NoModulesScreen({super.key, this.suspended = false});
  final bool suspended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniGym'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(suspended ? Icons.block : Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                suspended
                    ? 'Tu acceso está suspendido. Contacta al administrador de tu gimnasio.'
                    : 'Aún no tienes módulos asignados. Contacta al administrador de tu gimnasio.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              if (!suspended)
                TextButton(
                  onPressed: () => context.go('/profile'),
                  child: const Text('Mi perfil'),
                ),
              FilledButton.icon(
                onPressed: () => ref.read(firebaseAuthProvider).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

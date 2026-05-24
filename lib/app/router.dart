import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/providers.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/dashboard/owner_dashboard_screen.dart';
import '../features/dashboard/manager_dashboard_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/tenant_branding_screen.dart';
import '../features/staff/staff_screen.dart';
import 'app_shell.dart';
import 'app_theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authAsync = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final user = authAsync.valueOrNull;

      const publicRoutes = {'/login', '/register', '/forgot-password'};
      if (user == null) {
        return publicRoutes.contains(state.matchedLocation) ? null : '/login';
      }

      if (state.matchedLocation == '/login') {
        final role = await ref.read(currentUserRoleProvider.future);
        return _homeForRole(role);
      }

      return null;
    },
    routes: [
      // ── Auth (sin sidebar) ──────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        builder: (context, _) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, _) => const ForgotPasswordScreen(),
      ),

      // ── App autenticada (con sidebar) ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard/owner',
            builder: (context, _) => const OwnerDashboardScreen(),
          ),
          GoRoute(
            path: '/dashboard/manager',
            builder: (context, _) => const ManagerDashboardScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, _) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/settings/branding',
            builder: (context, _) => const TenantBrandingScreen(),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'owner' && role != 'superuser') {
                return '/dashboard/owner';
              }
              return null;
            },
          ),
          GoRoute(
            path: '/staff',
            builder: (context, _) => const StaffScreen(),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'owner' && role != 'superuser') {
                return '/dashboard/owner';
              }
              return null;
            },
          ),
          // ── Placeholder hasta implementar cada issue de UI ──────────────────
          GoRoute(
            path: '/superadmin',
            builder: (context, _) =>
                const _PlaceholderScreen('Consola Global'),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'superuser') return '/dashboard/owner';
              return null;
            },
          ),
          GoRoute(
            path: '/branches',
            builder: (context, _) =>
                const _PlaceholderScreen('Gestión de Sucursales'),
          ),
          GoRoute(
            path: '/members',
            builder: (context, _) =>
                const _PlaceholderScreen('Lista de Socios'),
          ),
          GoRoute(
            path: '/scanner',
            builder: (context, _) => const _PlaceholderScreen('Escáner QR'),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'staff' && role != 'owner') {
                return '/dashboard/owner';
              }
              return null;
            },
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Ruta no encontrada: ${state.uri}')),
    ),
  );
});

String _homeForRole(String? role) {
  return switch (role) {
    'superuser' => '/superadmin',
    'owner' => '/dashboard/owner',
    'staff' => '/dashboard/manager',
    _ => '/login',
  };
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title — próximamente',
          style: const TextStyle(color: OmniGymColors.textSecondary),
        ),
      ),
    );
  }
}

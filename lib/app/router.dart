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
import '../features/staff/staff_screen.dart';
import '../features/branches/branches_screen.dart';
import '../features/members/members_screen.dart';
import '../features/memberships/memberships_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/superadmin/tenants_screen.dart';
import '../features/superadmin/tenant_detail_screen.dart';
import '../features/superadmin/users_admin_screen.dart';
import 'app_shell.dart';
import 'app_theme.dart';

// Notifica a go_router cuando el estado de auth cambia, sin recrear el router.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) async {
      final user = ref.read(authStateProvider).valueOrNull;
      const publicRoutes = {'/login', '/register', '/forgot-password'};
      if (user == null) {
        return publicRoutes.contains(state.matchedLocation) ? null : '/login';
      }

      if (publicRoutes.contains(state.matchedLocation)) {
        try {
          final result = await user.getIdTokenResult();
          final role = result.claims?['role'] as String?;

          if (role != null) return _homeForRole(role);

          // Fallback: leer role de Firestore si no hay claims aún
          final doc = await ref
              .read(firestoreProvider)
              .collection('users')
              .doc(user.uid)
              .get();
          final fsRole = doc.data()?['role'] as String?;
          if (fsRole != null) return _homeForRole(fsRole);
        } catch (_) {
          // Si falla el token o Firestore, intentar con token cacheado
          try {
            final doc = await ref
                .read(firestoreProvider)
                .collection('users')
                .doc(user.uid)
                .get();
            final fsRole = doc.data()?['role'] as String?;
            if (fsRole != null) return _homeForRole(fsRole);
          } catch (_) {}
        }
        return '/dashboard/owner';
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
            path: '/settings',
            builder: (context, _) =>
                const TenantDetailScreen(isOwnerMode: true),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'owner' && role != 'superuser') {
                return '/dashboard/owner';
              }
              return null;
            },
          ),
          GoRoute(
            path: '/settings/branding',
            redirect: (context, state) => '/settings',
          ),
          GoRoute(
            path: '/settings/fiscal',
            redirect: (context, state) => '/settings',
          ),
          GoRoute(
            path: '/memberships',
            builder: (context, _) => const MembershipsScreen(),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'owner' && role != 'superuser') {
                return '/dashboard/owner';
              }
              return null;
            },
          ),
          GoRoute(
            path: '/reports',
            builder: (context, _) => const ReportsScreen(),
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
          // ── SuperAdmin ─────────────────────────────────────────────────────
          GoRoute(
            path: '/superadmin',
            builder: (context, _) => const TenantsScreen(),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'superuser') return '/dashboard/owner';
              return null;
            },
          ),
          GoRoute(
            path: '/superadmin/tenant/:tenantId',
            builder: (context, state) => TenantDetailScreen(
              tenantId: state.pathParameters['tenantId']!,
            ),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'superuser') return '/dashboard/owner';
              return null;
            },
          ),
          GoRoute(
            path: '/superadmin/users',
            builder: (context, _) => const UsersAdminScreen(),
            redirect: (context, state) async {
              final role = await ref.read(currentUserRoleProvider.future);
              if (role != 'superuser') return '/dashboard/owner';
              return null;
            },
          ),
          GoRoute(
            path: '/branches',
            builder: (context, _) => const BranchesScreen(),
          ),
          GoRoute(
            path: '/members',
            builder: (context, _) => const MembersScreen(),
          ),
          GoRoute(
            path: '/scanner',
            builder: (context, _) => const ScannerScreen(),
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

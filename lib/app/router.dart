import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/providers.dart';
import '../core/models/module_access.dart';
import '../features/staff/no_modules_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/staff_invitation_screen.dart';
import '../features/auth/staff_reset_password_screen.dart';
import '../features/dashboard/owner_dashboard_screen.dart';
import '../features/dashboard/manager_dashboard_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/staff/staff_screen.dart';
import '../features/branches/branches_screen.dart';
import '../features/members/members_screen.dart';
import '../features/facturacion/facturacion_screen.dart';
import '../features/memberships/memberships_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/scanner/kiosk_screen.dart';
import '../features/portal/member_portal_screen.dart';
import '../features/superadmin/tenants_screen.dart';
import '../features/superadmin/tenant_detail_screen.dart';
import '../features/superadmin/users_admin_screen.dart';
import '../features/superadmin/subscription_packages_screen.dart';
import '../features/billing/subscription_screen.dart';
import 'app_shell.dart';

// Notifica a go_router cuando el estado de auth cambia, sin recrear el router.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen(authStateProvider, (prev, next) => notifyListeners());
    _ref.listen(currentAppUserProvider, (prev, next) => notifyListeners());
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
      final path = state.uri.path;
      // Email links must remain usable even if a different personal/work account
      // is already signed in, and while activation changes the auth state.
      if (const {'/staff-invitation', '/staff-reset-password'}.contains(path)) {
        return null;
      }
      final auth = ref.read(authStateProvider);
      final user =
          auth.valueOrNull ??
          (auth.isLoading ? await ref.read(authStateProvider.future) : null);
      const publicRoutes = {'/login', '/register', '/forgot-password'};
      if (user == null) return publicRoutes.contains(path) ? null : '/login';
      final profile =
          ref.read(currentAppUserProvider).valueOrNull ??
          await ref.read(currentAppUserProvider.future);
      if (profile != null) {
        final home = ModuleAccess.home(profile);
        if (publicRoutes.contains(path)) return home;
        if (path == '/access-pending') return home == path ? null : home;
        if (home == '/access-pending') return home;
        if (path == '/access-suspended') return home == path ? null : home;
        if (home == '/access-suspended') return home;
        if (path == '/no-access') return home == path ? null : home;
        if (path.startsWith('/superadmin') &&
            profile.role.name != 'superuser') {
          return home;
        }
        if ((path.startsWith('/settings') || path == '/subscription') &&
            !const {'owner', 'superuser'}.contains(profile.role.name)) {
          return home;
        }
        if (path == '/staff' &&
            !const {
              'owner',
              'staff',
              'superuser',
            }.contains(profile.role.name)) {
          return home;
        }
        if (path == '/portal') return home;
        if (path == '/dashboard/owner' &&
            !const {'owner', 'superuser'}.contains(profile.role.name)) {
          return home;
        }
        final module = ModuleAccess.moduleForRoute(path);
        if (module != null && !ModuleAccess.has(profile, module)) return home;
        return null;
      }
      final token = await user.getIdTokenResult();
      final isMember =
          token.claims?['role'] == 'member' ||
          (await ref
                  .read(firestoreProvider)
                  .collectionGroup('members')
                  .where('uid', isEqualTo: user.uid)
                  .limit(1)
                  .get())
              .docs
              .isNotEmpty;
      final home = isMember ? '/portal' : '/no-access';
      return path == home ? null : home;
    },
    routes: [
      GoRoute(
        path: '/staff-invitation',
        builder: (_, state) => StaffInvitationScreen(
          id: state.uri.queryParameters['id'] ?? '',
          token: state.uri.queryParameters['token'] ?? '',
          code: state.uri.queryParameters['oobCode'] ?? '',
        ),
      ),
      GoRoute(
        path: '/staff-reset-password',
        builder: (_, state) => StaffResetPasswordScreen(
          code: state.uri.queryParameters['oobCode'] ?? '',
        ),
      ),
      GoRoute(
        path: '/access-pending',
        builder: (_, _) => const NoModulesScreen(pending: true),
      ),
      GoRoute(path: '/no-access', builder: (_, _) => const NoModulesScreen()),
      GoRoute(
        path: '/access-suspended',
        builder: (_, _) => const NoModulesScreen(suspended: true),
      ),
      // ── Auth (sin sidebar) ──────────────────────────────────────────────────
      GoRoute(path: '/login', builder: (context, _) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, _) => const ForgotPasswordScreen(),
      ),

      // ── Kiosko (fullscreen, sin sidebar) ───────────────────────────────────
      GoRoute(path: '/kiosk', builder: (context, _) => const KioskScreen()),

      // ── Portal del socio (fullscreen, sin sidebar) ───────────────────────
      GoRoute(
        path: '/portal',
        builder: (context, _) => const MemberPortalScreen(),
      ),

      // ── App autenticada (con sidebar) ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
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
            path: '/subscription',
            builder: (context, _) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: '/memberships',
            builder: (context, _) => const MembershipsScreen(),
          ),
          GoRoute(
            path: '/facturacion',
            builder: (context, _) => const FacturacionScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, _) => const ReportsScreen(),
          ),
          GoRoute(path: '/staff', builder: (context, _) => const StaffScreen()),
          // ── SuperAdmin ─────────────────────────────────────────────────────
          GoRoute(
            path: '/superadmin',
            builder: (context, _) => const TenantsScreen(),
          ),
          GoRoute(
            path: '/superadmin/tenant/:tenantId',
            builder: (context, state) =>
                TenantDetailScreen(tenantId: state.pathParameters['tenantId']!),
          ),
          GoRoute(
            path: '/superadmin/users',
            builder: (context, _) => const UsersAdminScreen(),
          ),
          GoRoute(
            path: '/superadmin/packages',
            builder: (context, _) => const SubscriptionPackagesScreen(),
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
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Ruta no encontrada: ${state.uri}'))),
  );
});

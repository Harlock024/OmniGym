import 'app_user.dart';

/// Keys persisted in /users/{uid}.permissions. Payments and plans share a page.
const appModules = [
  (key: 'dashboard', label: 'Dashboard', route: '/dashboard/manager'),
  (key: 'branches', label: 'Sucursales', route: '/branches'),
  (key: 'members', label: 'Socios', route: '/members'),
  (key: 'scanner', label: 'Escáner QR', route: '/scanner'),
  (key: 'memberships', label: 'Membresías y pagos', route: '/memberships'),
  (key: 'billing', label: 'Facturación', route: '/facturacion'),
  (key: 'reports', label: 'Reportes', route: '/reports'),
];

class ModuleAccess {
  static bool has(AppUser? user, String module) {
    if (user == null || user.status != UserStatus.active) return false;
    if (user.role == UserRole.owner || user.role == UserRole.superuser) {
      return true;
    }
    if (user.permissions.containsKey(module)) {
      return user.permissions[module] == true;
    }
    // Preserve the former staff's dashboard/scanner until the owner edits it.
    // Receptionists always default to no access, including missing map keys.
    return user.role == UserRole.staff &&
        user.permissions.isEmpty &&
        const {'dashboard', 'scanner'}.contains(module);
  }

  static Map<String, bool> permissionsOf(AppUser user) => {
    for (final module in appModules) module.key: has(user, module.key),
  };

  static bool canManage(AppUser? actor, AppUser target) {
    if (actor == null ||
        actor.status != UserStatus.active ||
        actor.id == target.id) {
      return false;
    }
    if (target.role == UserRole.owner || target.role == UserRole.superuser) {
      return false;
    }
    if (actor.role == UserRole.superuser) return true;
    if (actor.tenantId == null || actor.tenantId != target.tenantId) {
      return false;
    }
    return actor.role == UserRole.owner ||
        (actor.role == UserRole.staff && target.role == UserRole.receptionist);
  }

  static String? moduleForRoute(String path) {
    if (path.startsWith('/dashboard/')) return 'dashboard';
    if (path == '/kiosk') return 'scanner';
    for (final module in appModules) {
      if (path == module.route || path.startsWith('${module.route}/')) {
        return module.key;
      }
    }
    return null;
  }

  static String home(AppUser user) {
    if (user.status == UserStatus.pending) return '/access-pending';
    if (user.status != UserStatus.active) return '/access-suspended';
    if (user.role == UserRole.superuser) return '/superadmin';
    if (user.role == UserRole.owner) return '/dashboard/owner';
    for (final module in appModules) {
      if (has(user, module.key)) return module.route;
    }
    return user.role == UserRole.staff ? '/staff' : '/no-access';
  }
}

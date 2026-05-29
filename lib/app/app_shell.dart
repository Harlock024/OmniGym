import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/providers.dart';
import 'app_theme.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
  });

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final user = ref.watch(currentAppUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Row(
        children: [
          _Sidebar(
            role: role,
            location: location,
            userName: user?.name ?? '',
            userEmail: user?.email ?? '',
            photoUrl: user?.photoUrl,
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: OmniGymColors.border,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ─── Nav item model ────────────────────────────────────────────────────────────

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

const _superuserItems = [
  _NavItem(icon: Icons.business_rounded, label: 'Empresas', route: '/superadmin'),
  _NavItem(icon: Icons.manage_accounts_rounded, label: 'Administrar usuarios', route: '/superadmin/users'),
];

const _ownerItems = [
  _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', route: '/dashboard/owner'),
  _NavItem(icon: Icons.location_city_rounded, label: 'Sucursales', route: '/branches'),
  _NavItem(icon: Icons.fitness_center, label: 'Socios', route: '/members'),
  _NavItem(icon: Icons.badge_rounded, label: 'Staff', route: '/staff'),
  _NavItem(icon: Icons.settings_rounded, label: 'Configuración', route: '/settings/branding'),
];

const _staffItems = [
  _NavItem(icon: Icons.dashboard_rounded, label: 'Mi Sucursal', route: '/dashboard/manager'),
  _NavItem(icon: Icons.qr_code_scanner, label: 'Escáner QR', route: '/scanner'),
];

// ─── Sidebar ──────────────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.role,
    required this.location,
    required this.userName,
    required this.userEmail,
    this.photoUrl,
  });

  final String? role;
  final String location;
  final String userName;
  final String userEmail;
  final String? photoUrl;

  List<_NavItem> get _items => switch (role) {
        'superuser' => _superuserItems,
        'owner' => _ownerItems,
        'staff' => _staffItems,
        _ => const [],
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 200,
      color: OmniGymColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LogoHeader(),
          const Divider(color: OmniGymColors.border, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: _items
                  .map((item) => _NavTile(
                        item: item,
                        isActive: location == item.route ||
                            location.startsWith('${item.route}/'),
                      ))
                  .toList(),
            ),
          ),
          const Divider(color: OmniGymColors.border, height: 1),
          _UserFooter(
            name: userName,
            email: userEmail,
            photoUrl: photoUrl,
            onSignOut: () => ref.read(firebaseAuthProvider).signOut(),
          ),
        ],
      ),
    );
  }
}

// ─── Logo header ──────────────────────────────────────────────────────────────

class _LogoHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: OmniGymColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.fitness_center, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'OmniGym',
            style: TextStyle(
              color: OmniGymColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Nav tile ─────────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.isActive});

  final _NavItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(item.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? OmniGymColors.primary.withAlpha(30)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? Border.all(color: OmniGymColors.primary.withAlpha(70))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: isActive
                      ? OmniGymColors.primary
                      : OmniGymColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isActive
                          ? OmniGymColors.primary
                          : OmniGymColors.textSecondary,
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── User footer ──────────────────────────────────────────────────────────────

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.name,
    required this.email,
    required this.onSignOut,
    this.photoUrl,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: OmniGymColors.primary,
            backgroundImage:
                photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: OmniGymColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: const TextStyle(
                    color: OmniGymColors.textSecondary,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.logout,
              size: 16,
              color: OmniGymColors.textSecondary,
            ),
            onPressed: onSignOut,
            tooltip: 'Cerrar sesión',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

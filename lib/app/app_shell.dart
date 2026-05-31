import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/providers.dart';
import 'app_theme.dart';

// ─── Shell scope ──────────────────────────────────────────────────────────────
// Exposes the outer Scaffold's openDrawer callback to descendant widgets.

class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  final VoidCallback openDrawer;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => openDrawer != old.openDrawer;
}

// ─── Hamburger button for use inside screen AppBars / headers ─────────────────

class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ShellScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.menu_rounded, color: OmniGymColors.textSecondary),
      onPressed: scope.openDrawer,
      tooltip: 'Menú',
    );
  }
}

// ─── Nav item / section model ─────────────────────────────────────────────────

sealed class _NavEntry {
  const _NavEntry();
}

class _NavItem extends _NavEntry {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

class _NavSection extends _NavEntry {
  const _NavSection(this.label);
  final String label;
}

const _superuserItems = <_NavEntry>[
  _NavItem(icon: Icons.business_rounded, label: 'Empresas', route: '/superadmin'),
  _NavItem(icon: Icons.manage_accounts_rounded, label: 'Administrar usuarios', route: '/superadmin/users'),
];

const _ownerItems = <_NavEntry>[
  _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', route: '/dashboard/owner'),
  _NavItem(icon: Icons.location_city_rounded, label: 'Sucursales', route: '/branches'),
  _NavItem(icon: Icons.fitness_center, label: 'Socios', route: '/members'),
  _NavItem(icon: Icons.card_membership_rounded, label: 'Membresías', route: '/memberships'),
  _NavItem(icon: Icons.bar_chart_rounded, label: 'Reportes', route: '/reports'),
  _NavItem(icon: Icons.badge_rounded, label: 'Staff', route: '/staff'),
  _NavItem(icon: Icons.settings_rounded, label: 'Configuración', route: '/settings'),
];

const _staffItems = <_NavEntry>[
  _NavItem(icon: Icons.dashboard_rounded, label: 'Mi Sucursal', route: '/dashboard/manager'),
  _NavItem(icon: Icons.qr_code_scanner, label: 'Escáner QR', route: '/scanner'),
];

// ─── AppShell ─────────────────────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
  });

  final Widget child;
  final String location;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _drawerKey = GlobalKey<ScaffoldState>();

  void _openDrawer() => _drawerKey.currentState?.openDrawer();

  static List<_NavItem> _navItems(String? role) => switch (role) {
        'superuser' => _superuserItems.whereType<_NavItem>().toList(),
        'owner' => _ownerItems.whereType<_NavItem>().toList(),
        'staff' => _staffItems.whereType<_NavItem>().toList(),
        _ => const [],
      };

  static int _selectedIndex(List<_NavItem> items, String location) {
    for (int i = 0; i < items.length; i++) {
      final route = items[i].route;
      if (location == route || location.startsWith('$route/')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final user = ref.watch(currentAppUserProvider).valueOrNull;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < Breakpoints.mobile;
    final isTablet =
        width >= Breakpoints.mobile && width < Breakpoints.tablet;

    final sidebarContent = _SidebarContent(
      role: role,
      location: widget.location,
      userName: user?.name ?? '',
      userEmail: user?.email ?? '',
      photoUrl: user?.photoUrl,
    );

    // ── Mobile: full-width screen + Drawer ────────────────────────────────────
    if (isMobile) {
      return ShellScope(
        openDrawer: _openDrawer,
        child: Scaffold(
          key: _drawerKey,
          backgroundColor: OmniGymColors.background,
          drawer: Drawer(
            backgroundColor: OmniGymColors.surface,
            width: 280,
            child: sidebarContent,
          ),
          body: widget.child,
        ),
      );
    }

    // ── Tablet: icon-only rail sidebar ────────────────────────────────────────
    if (isTablet) {
      final items = _navItems(role);
      final selectedIdx = _selectedIndex(items, widget.location);
      return Scaffold(
        backgroundColor: OmniGymColors.background,
        body: Row(
          children: [
            _RailSidebar(
              items: items,
              selectedIndex: selectedIdx,
              location: widget.location,
              userName: user?.name ?? '',
              photoUrl: user?.photoUrl,
            ),
            const VerticalDivider(
                width: 1, thickness: 1, color: OmniGymColors.border),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    // ── Desktop: full sidebar ─────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Row(
        children: [
          SizedBox(width: 200, child: sidebarContent),
          const VerticalDivider(
              width: 1, thickness: 1, color: OmniGymColors.border),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

// ─── Sidebar content (shared between desktop and drawer) ─────────────────────

class _SidebarContent extends ConsumerWidget {
  const _SidebarContent({
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

  List<_NavEntry> get _items => switch (role) {
        'superuser' => _superuserItems,
        'owner' => _ownerItems,
        'staff' => _staffItems,
        _ => const [],
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
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
                  .map((entry) => switch (entry) {
                        _NavItem item => _NavTile(
                            item: item,
                            isActive: location == item.route ||
                                location.startsWith('${item.route}/'),
                          ),
                        _NavSection section =>
                          _NavSectionHeader(label: section.label),
                      })
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

// ─── Rail sidebar (tablet) ────────────────────────────────────────────────────

class _RailSidebar extends ConsumerWidget {
  const _RailSidebar({
    required this.items,
    required this.selectedIndex,
    required this.location,
    required this.userName,
    this.photoUrl,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final String location;
  final String userName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 72,
      color: OmniGymColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: OmniGymColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fitness_center,
                  color: Colors.white, size: 18),
            ),
          ),
          const Divider(color: OmniGymColors.border, height: 1),
          const SizedBox(height: 4),
          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: items.asMap().entries.map((entry) {
                final isActive = entry.key == selectedIndex;
                return _RailTile(item: entry.value, isActive: isActive);
              }).toList(),
            ),
          ),
          const Divider(color: OmniGymColors.border, height: 1),
          // User avatar + signout
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: OmniGymColors.primary,
                  backgroundImage:
                      photoUrl != null ? NetworkImage(photoUrl!) : null,
                  child: photoUrl == null
                      ? Text(
                          userName.isNotEmpty
                              ? userName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        )
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.logout,
                      size: 16, color: OmniGymColors.textSecondary),
                  onPressed: () =>
                      ref.read(firebaseAuthProvider).signOut(),
                  tooltip: 'Cerrar sesión',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({required this.item, required this.isActive});
  final _NavItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Tooltip(
        message: item.label,
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go(item.route),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? OmniGymColors.primary.withAlpha(30)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isActive
                    ? Border.all(color: OmniGymColors.primary.withAlpha(70))
                    : null,
              ),
              child: Icon(
                item.icon,
                size: 20,
                color: isActive
                    ? OmniGymColors.primary
                    : OmniGymColors.textSecondary,
              ),
            ),
          ),
        ),
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
            child: const Icon(Icons.fitness_center,
                color: Colors.white, size: 18),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

// ─── Nav section header ───────────────────────────────────────────────────────

class _NavSectionHeader extends StatelessWidget {
  const _NavSectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: OmniGymColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
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
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
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
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

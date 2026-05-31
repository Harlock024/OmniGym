import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/app_user.dart';
import '../../core/models/branch.dart';
import '../../core/providers/providers.dart';
import 'invite_staff_sheet.dart';
import 'staff_providers.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: context.isMobile ? const DrawerMenuButton() : null,
        automaticallyImplyLeading: false,
        title: const Text('Equipo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(firebaseAuthProvider).signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          const _StaffFilters(),
          const Expanded(child: _StaffList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openInviteSheet(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Invitar'),
      ),
    );
  }

  void _openInviteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const InviteStaffSheet(),
    );
  }
}

// ─── Filtros ──────────────────────────────────────────────────────────────────

class _StaffFilters extends ConsumerWidget {
  const _StaffFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleFilter = ref.watch(staffRoleFilterProvider);
    final statusFilter = ref.watch(staffStatusFilterProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('Owner'),
            selected: roleFilter == UserRole.owner,
            onSelected: (v) => ref.read(staffRoleFilterProvider.notifier).state =
                v ? UserRole.owner : null,
          ),
          FilterChip(
            label: const Text('Staff'),
            selected: roleFilter == UserRole.staff,
            onSelected: (v) => ref.read(staffRoleFilterProvider.notifier).state =
                v ? UserRole.staff : null,
          ),
          const VerticalDivider(width: 16),
          FilterChip(
            label: const Text('Activos'),
            selected: statusFilter == UserStatus.active,
            onSelected: (v) =>
                ref.read(staffStatusFilterProvider.notifier).state =
                    v ? UserStatus.active : null,
          ),
          FilterChip(
            label: const Text('Suspendidos'),
            selected: statusFilter == UserStatus.suspended,
            onSelected: (v) =>
                ref.read(staffStatusFilterProvider.notifier).state =
                    v ? UserStatus.suspended : null,
          ),
        ],
      ),
    );
  }
}

// ─── Lista ────────────────────────────────────────────────────────────────────

class _StaffList extends ConsumerWidget {
  const _StaffList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(filteredStaffProvider);
    final currentUser = ref.watch(currentUserProvider);

    return staffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (staff) {
        // Ocultar al superuser de la lista para owners
        final visible = staff
            .where((u) => u.role != UserRole.superuser)
            .toList();

        if (visible.isEmpty) {
          return const Center(child: Text('No hay operadores registrados.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          itemCount: visible.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _StaffTile(
            user: visible[i],
            isSelf: visible[i].id == currentUser?.uid,
          ),
        );
      },
    );
  }
}

// ─── Item ─────────────────────────────────────────────────────────────────────

class _StaffTile extends ConsumerWidget {
  const _StaffTile({required this.user, required this.isSelf});

  final AppUser user;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isActive = user.status == UserStatus.active;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: TextStyle(color: cs.onPrimaryContainer),
          ),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(user.email),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            _RoleChip(role: user.role),
            _StatusChip(isActive: isActive),
            if (!isSelf)
              _ActionMenu(user: user),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = switch (role) {
      UserRole.owner => 'Owner',
      UserRole.staff => 'Staff',
      UserRole.superuser => 'Super',
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      backgroundColor: cs.secondaryContainer,
      labelStyle: TextStyle(color: cs.onSecondaryContainer),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Activo' : 'Suspendido',
        style: TextStyle(
          fontSize: 11,
          color: isActive ? cs.onPrimaryContainer : cs.onErrorContainer,
        ),
      ),
    );
  }
}

// ─── Menú de acciones ─────────────────────────────────────────────────────────

class _ActionMenu extends ConsumerWidget {
  const _ActionMenu({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = user.status == UserStatus.active;

    return PopupMenuButton<_Action>(
      onSelected: (action) => _handleAction(context, ref, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: isActive ? _Action.suspend : _Action.activate,
          child: ListTile(
            leading: Icon(isActive ? Icons.block : Icons.check_circle_outline),
            title: Text(isActive ? 'Suspender' : 'Activar'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (user.role == UserRole.staff)
          const PopupMenuItem(
            value: _Action.changeBranch,
            child: ListTile(
              leading: Icon(Icons.store_outlined),
              title: Text('Cambiar sucursal'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _Action action,
  ) async {
    final repo = ref.read(userRepositoryProvider);

    switch (action) {
      case _Action.suspend:
        await repo.updateStatus(user.id, UserStatus.suspended);
      case _Action.activate:
        await repo.updateStatus(user.id, UserStatus.active);
      case _Action.changeBranch:
        if (context.mounted) _showChangeBranchDialog(context, ref);
    }
  }

  void _showChangeBranchDialog(BuildContext context, WidgetRef ref) {
    final tenantIdAsync = ref.read(activeTenantIdFutureProvider);
    tenantIdAsync.whenData((tenantId) {
      if (tenantId == null || !context.mounted) return;
      final branchesAsync = ref.read(
        StreamProvider((r) =>
            r.read(branchRepositoryProvider).watchAll(tenantId)).future,
      );
      branchesAsync.then((branches) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (_) => _ChangeBranchDialog(user: user, branches: branches),
        );
      });
    });
  }
}

enum _Action { suspend, activate, changeBranch }

class _ChangeBranchDialog extends ConsumerWidget {
  const _ChangeBranchDialog({required this.user, required this.branches});
  final AppUser user;
  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Cambiar sucursal'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: branches.length,
          itemBuilder: (_, i) {
            final branch = branches[i];
            return ListTile(
              title: Text(branch.name),
              selected: branch.id == user.branchId,
              onTap: () async {
                await ref
                    .read(userRepositoryProvider)
                    .updateBranchId(user.id, branch.id);
                if (context.mounted) Navigator.pop(context);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

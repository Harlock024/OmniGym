import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/app_user.dart';
import '../../core/models/tenant.dart';
import '../../core/providers/providers.dart';
import 'superadmin_providers.dart';

class UsersAdminScreen extends ConsumerWidget {
  const UsersAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(filteredUsersProvider);
    final tenantMap = ref.watch(tenantMapProvider);
    final search = ref.watch(userSearchProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(searchValue: search),
          // Column headers
          _ColumnHeaders(),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: OmniGymColors.textSecondary)),
              ),
              data: (users) => users.isEmpty
                  ? _EmptyState(hasSearch: search.isNotEmpty)
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: users.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: OmniGymColors.border),
                      itemBuilder: (context, i) => _UserRow(
                        user: users[i],
                        tenant: tenantMap[users[i].tenantId],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.searchValue});
  final String searchValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: OmniGymColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (context.isMobile) const DrawerMenuButton(),
              const Text(
                'Administrar usuarios',
                style: TextStyle(
                  color: OmniGymColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Consumer(builder: (_, ref, __) {
                final count = ref.watch(allUsersProvider).valueOrNull?.length ?? 0;
                return Text(
                  '$count usuarios',
                  style: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
                );
              }),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Asigna empresa y permisos de acceso a cada usuario.',
            style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) =>
                  ref.read(userSearchProvider.notifier).state = v,
              style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, correo o empresa...',
                hintStyle: const TextStyle(
                    color: OmniGymColors.textSecondary, fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    color: OmniGymColors.textSecondary, size: 18),
                filled: true,
                fillColor: OmniGymColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OmniGymColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OmniGymColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OmniGymColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Encabezados ─────────────────────────────────────────────────────────────

class _ColumnHeaders extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: OmniGymColors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: OmniGymColors.surface,
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('NOMBRE', style: style)),
          Expanded(flex: 3, child: Text('CORREO', style: style)),
          Expanded(flex: 2, child: Text('EMPRESA', style: style)),
          SizedBox(width: 90, child: Text('ROL', style: style)),
          SizedBox(width: 100, child: Text('ACCIONES', style: style)),
        ],
      ),
    );
  }
}

// ─── Fila de usuario ──────────────────────────────────────────────────────────

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user, this.tenant});
  final AppUser user;
  final Tenant? tenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Nombre
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: OmniGymColors.primary.withAlpha(40),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: OmniGymColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    user.name,
                    style: const TextStyle(
                        color: OmniGymColors.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Correo
          Expanded(
            flex: 3,
            child: Text(
              user.email,
              style: const TextStyle(
                  color: OmniGymColors.textSecondary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Empresa
          Expanded(
            flex: 2,
            child: tenant != null
                ? _TenantTag(tenant: tenant!)
                : const Text(
                    'Sin empresa',
                    style: TextStyle(
                        color: OmniGymColors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
          ),
          // Rol
          SizedBox(
            width: 90,
            child: _RoleChip(role: user.role),
          ),
          // Acciones
          SizedBox(
            width: 100,
            child: Row(
              children: [
                _ActionIcon(
                  icon: Icons.table_chart_outlined,
                  tooltip: 'Permisos',
                  onTap: () => _showPermissionsDialog(context, ref),
                ),
                _ActionIcon(
                  icon: Icons.lock_outline,
                  tooltip: 'Asignar rol',
                  onTap: () => _showRoleDialog(context, ref),
                ),
                _ActionIcon(
                  icon: Icons.person_remove_outlined,
                  tooltip: 'Eliminar',
                  color: OmniGymColors.errorRed,
                  onTap: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRoleDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _RoleDialog(user: user, ref: ref),
    );
  }

  void _showPermissionsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _PermissionsDialog(user: user, ref: ref),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: OmniGymColors.card,
        title: const Text('¿Eliminar usuario?',
            style: TextStyle(color: OmniGymColors.textPrimary)),
        content: Text(
          'Se eliminará el registro de ${user.name} (${user.email}). Esta acción no se puede deshacer.',
          style: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OmniGymColors.errorRed),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(userRepositoryProvider).delete(user.id);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ─── Tag de empresa ───────────────────────────────────────────────────────────

class _TenantTag extends StatelessWidget {
  const _TenantTag({required this.tenant});
  final Tenant tenant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: OmniGymColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Text(
        tenant.name,
        style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─── Chip de rol ──────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      UserRole.superuser => ('superuser', Colors.amber),
      UserRole.owner => ('owner', OmniGymColors.primary),
      UserRole.staff => ('staff', OmniGymColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Icono de acción ──────────────────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = OmniGymColors.textSecondary,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}

// ─── Dialog: Asignar rol ──────────────────────────────────────────────────────

class _RoleDialog extends StatefulWidget {
  const _RoleDialog({required this.user, required this.ref});
  final AppUser user;
  final WidgetRef ref;

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late UserRole _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.user.role == UserRole.superuser
        ? UserRole.owner
        : widget.user.role;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OmniGymColors.card,
      title: Text(
        'Rol de ${widget.user.name}',
        style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoleOption(
            role: UserRole.owner,
            label: 'owner (admin)',
            description: 'Puede ver y administrar usuarios de su empresa',
            selected: _selected == UserRole.owner,
            onTap: () => setState(() => _selected = UserRole.owner),
          ),
          const SizedBox(height: 12),
          _RoleOption(
            role: UserRole.staff,
            label: 'staff',
            description: 'Usuario regular sin acceso al panel de administración',
            selected: _selected == UserRole.staff,
            onTap: () => setState(() => _selected = UserRole.staff),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.ref
                      .read(userRepositoryProvider)
                      .updateRole(widget.user.id, _selected);
                  if (context.mounted) Navigator.pop(context);
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.role,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Radio<bool>(
            value: true,
            groupValue: selected,
            onChanged: (_) => onTap(),
            activeColor: OmniGymColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      color: OmniGymColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  description,
                  style: const TextStyle(
                      color: OmniGymColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dialog: Permisos de módulos ──────────────────────────────────────────────

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({required this.user, required this.ref});
  final AppUser user;
  final WidgetRef ref;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late Map<String, bool> _perms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Start with existing permissions; missing keys default to true
    _perms = {
      for (final m in kOmniGymModules)
        m.key: widget.user.permissions[m.key] ?? true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OmniGymColors.card,
      title: Text(
        'Permisos de ${widget.user.name}',
        style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: kOmniGymModules.map((m) {
            return CheckboxListTile(
              value: _perms[m.key] ?? true,
              onChanged: (v) =>
                  setState(() => _perms[m.key] = v ?? false),
              title: Text(
                m.label,
                style: const TextStyle(
                    color: OmniGymColors.textPrimary, fontSize: 13),
              ),
              activeColor: OmniGymColors.primary,
              controlAffinity: ListTileControlAffinity.trailing,
              dense: true,
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.ref
                      .read(userRepositoryProvider)
                      .updatePermissions(widget.user.id, _perms);
                  if (context.mounted) Navigator.pop(context);
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch});
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.people_outline,
            size: 48,
            color: OmniGymColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch
                ? 'Sin resultados para esa búsqueda'
                : 'No hay usuarios registrados',
            style: const TextStyle(
                color: OmniGymColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_user.dart';
import '../../core/models/module_access.dart';
import '../../core/providers/providers.dart';

/// Anchored popover. Edits stay local until Save; dismissal cancels them.
class ModulePermissionsButton extends ConsumerWidget {
  const ModulePermissionsButton({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(currentAppUserProvider).valueOrNull;
    if (!ModuleAccess.canManage(actor, user)) return const SizedBox.shrink();
    return Builder(
      builder: (anchorContext) {
        return IconButton(
          tooltip: 'Permisos de ${user.name}',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) =>
                _PermissionsPopover(user: user, anchorContext: anchorContext),
          ),
        );
      },
    );
  }
}

class _PermissionsPopover extends ConsumerStatefulWidget {
  const _PermissionsPopover({required this.user, required this.anchorContext});
  final AppUser user;
  final BuildContext anchorContext;

  @override
  ConsumerState<_PermissionsPopover> createState() =>
      _PermissionsPopoverState();
}

class _PermissionsPopoverState extends ConsumerState<_PermissionsPopover> {
  late final Map<String, bool> _permissions = ModuleAccess.permissionsOf(
    widget.user,
  );
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .updatePermissions(widget.user.id, _permissions);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'No se pudieron guardar los permisos. Verifica tus accesos e inténtalo de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(currentAppUserProvider).valueOrNull;
    final canManage = ModuleAccess.canManage(actor, widget.user);
    final size = MediaQuery.sizeOf(context);
    final box = widget.anchorContext.findRenderObject() as RenderBox?;
    final point = box?.localToGlobal(Offset.zero) ?? Offset(size.width / 2, 80);
    final width = (size.width - 32).clamp(0.0, 360.0);
    final left = (point.dx + (box?.size.width ?? 0) - width).clamp(
      16.0,
      size.width - width - 16,
    );
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: (point.dy - MediaQuery.paddingOf(context).top).clamp(
              16.0,
              120.0,
            ),
            width: width,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height - 160),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Módulos de ${widget.user.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final module in appModules)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(module.label),
                          subtitle: ModuleAccess.isEnabled(module.key)
                              ? null
                              : const Text('Temporalmente deshabilitado'),
                          value: _permissions[module.key] == true,
                          onChanged:
                              !_saving &&
                                  canManage &&
                                  ModuleAccess.canUse(actor, module.key)
                              ? (value) => setState(
                                  () =>
                                      _permissions[module.key] = value == true,
                                )
                              : null,
                        ),
                      if (actor?.role == UserRole.staff)
                        const Text(
                          'Puedes modificar únicamente los módulos que tienes autorizados.',
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: _saving || !canManage ? null : _save,
                            child: Text(_saving ? 'Guardando…' : 'Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

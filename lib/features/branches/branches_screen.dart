import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_theme.dart';
import '../../core/models/branch.dart';
import '../../core/providers/providers.dart';
import '../superadmin/mexico_data.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final _branchesProvider = StreamProvider<List<Branch>>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  if (tenantId == null) { yield []; return; }
  yield* ref.watch(branchRepositoryProvider).watchAll(tenantId);
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(_branchesProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onAdd: () => _openForm(context, ref, null)),
          Expanded(
            child: branchesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: OmniGymColors.textSecondary)),
              ),
              data: (branches) => branches.isEmpty
                  ? _EmptyState(onAdd: () => _openForm(context, ref, null))
                  : _BranchGrid(branches: branches),
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref, Branch? branch) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BranchFormDialog(existing: branch),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OmniGymColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Sucursales',
            style: TextStyle(
              color: OmniGymColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva sucursal'),
          ),
        ],
      ),
    );
  }
}

// ─── Grid de sucursales ───────────────────────────────────────────────────────

class _BranchGrid extends ConsumerWidget {
  const _BranchGrid({required this.branches});
  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 220,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: branches.length,
      itemBuilder: (context, i) => _BranchCard(branch: branches[i]),
    );
  }
}

// ─── Card de sucursal ─────────────────────────────────────────────────────────

class _BranchCard extends ConsumerWidget {
  const _BranchCard({required this.branch});
  final Branch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantIdAsync = ref.watch(activeTenantIdFutureProvider);
    final tenantId = tenantIdAsync.valueOrNull ?? '';

    final activeMembersAsync = ref.watch(
      activeMemberCountProvider((tenantId: tenantId, branchId: branch.id)),
    );
    final checkInsAsync = ref.watch(
      todayCheckInCountProvider((tenantId: tenantId, branchId: branch.id)),
    );

    return Container(
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mini-mapa o placeholder
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: branch.location != null
                  ? _MiniMap(location: branch.location!)
                  : _MapPlaceholder(name: branch.name),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        branch.name,
                        style: const TextStyle(
                          color: OmniGymColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _ActiveBadge(isActive: branch.isActive),
                  ],
                ),
                if (branch.address != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${branch.address!.street}, ${branch.address!.city}',
                    style: const TextStyle(
                      color: OmniGymColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.people_outline,
                      value: activeMembersAsync.valueOrNull?.toString() ?? '—',
                      label: 'socios',
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.login,
                      value: checkInsAsync.valueOrNull?.toString() ?? '—',
                      label: 'hoy',
                    ),
                    const Spacer(),
                    // Acciones
                    _CardActions(branch: branch),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: OmniGymColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? OmniGymColors.success : OmniGymColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        isActive ? 'Activa' : 'Inactiva',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CardActions extends ConsumerWidget {
  const _CardActions({required this.branch});
  final Branch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16, color: OmniGymColors.textSecondary),
      color: OmniGymColors.card,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: const Row(children: [
            Icon(Icons.edit_outlined, size: 16),
            SizedBox(width: 8),
            Text('Editar'),
          ]),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(children: [
            Icon(branch.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 16),
            const SizedBox(width: 8),
            Text(branch.isActive ? 'Desactivar' : 'Activar'),
          ]),
        ),
      ],
      onSelected: (action) async {
        if (action == 'edit') {
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _BranchFormDialog(existing: branch),
            );
          }
        } else if (action == 'toggle') {
          final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
              ?? await ref.read(activeTenantIdFutureProvider.future);
          if (tenantId != null) {
            await ref.read(branchRepositoryProvider).setActive(
                  tenantId,
                  branch.id,
                  isActive: !branch.isActive,
                );
          }
        }
      },
    );
  }
}

// ─── Mini-mapa ────────────────────────────────────────────────────────────────

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.location});
  final BranchLocation location;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(location.latitude, location.longitude);
    return FlutterMap(
      options: MapOptions(
        initialCenter: point,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.omnigym.app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 30,
              height: 30,
              child: const Icon(Icons.location_pin, color: OmniGymColors.primary, size: 30),
            ),
          ],
        ),
      ],
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: OmniGymColors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_on_outlined,
              color: OmniGymColors.textSecondary, size: 28),
          const SizedBox(height: 4),
          Text(
            'Sin ubicación',
            style: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store_outlined,
              size: 52, color: OmniGymColors.textSecondary),
          const SizedBox(height: 12),
          const Text(
            'Aún no hay sucursales',
            style: TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crea la primera sucursal de tu gimnasio.',
            style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva sucursal'),
          ),
        ],
      ),
    );
  }
}

// ─── Formulario de sucursal ───────────────────────────────────────────────────

class _BranchFormDialog extends ConsumerStatefulWidget {
  const _BranchFormDialog({this.existing});
  final Branch? existing;

  @override
  ConsumerState<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends ConsumerState<_BranchFormDialog> {
  final _nameCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  String? _state;
  String? _municipality;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _nameCtrl.text = b.name;
      _isActive = b.isActive;
      _state = b.address?.state;
      _municipality = b.address?.municipality ?? b.address?.city;
      _streetCtrl.text = b.address?.street ?? '';
      _postalCtrl.text = b.address?.postalCode ?? '';
      if (b.location != null) {
        _latCtrl.text = b.location!.latitude.toString();
        _lngCtrl.text = b.location!.longitude.toString();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _streetCtrl.dispose();
    _postalCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
          ?? await ref.read(activeTenantIdFutureProvider.future);
      if (tenantId == null) throw Exception('Tenant no encontrado.');

      BranchAddress? address;
      if (_streetCtrl.text.trim().isNotEmpty) {
        address = BranchAddress(
          street: _streetCtrl.text.trim(),
          city: _municipality ?? _state ?? '',
          state: _state ?? '',
          postalCode: _postalCtrl.text.trim(),
          municipality: _municipality,
        );
      }

      BranchLocation? location;
      final lat = double.tryParse(_latCtrl.text.trim());
      final lng = double.tryParse(_lngCtrl.text.trim());
      if (lat != null && lng != null) {
        location = BranchLocation(latitude: lat, longitude: lng);
      }

      final repo = ref.read(branchRepositoryProvider);

      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          isActive: _isActive,
          address: address,
          location: location,
        );
        await repo.update(updated);
      } else {
        final branch = Branch(
          id: '',
          tenantId: tenantId,
          name: _nameCtrl.text.trim(),
          isActive: _isActive,
          address: address,
          location: location,
        );
        await repo.create(branch);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: OmniGymColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _isEdit ? 'Editar sucursal' : 'Nueva sucursal',
                    style: const TextStyle(
                      color: OmniGymColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: OmniGymColors.textSecondary, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _FormField(controller: _nameCtrl, label: 'Nombre de la sucursal'),
              const SizedBox(height: 14),
              _FormField(controller: _streetCtrl, label: 'Dirección / Calle'),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _FormDropdown<String>(
                      label: 'Estado',
                      value: _state,
                      items: MexicoData.states
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setState(() { _state = v; _municipality = null; }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormDropdown<String>(
                      label: 'Municipio',
                      value: _municipality,
                      items: MexicoData.getMunicipalities(_state)
                          .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) => setState(() => _municipality = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _FormField(controller: _postalCtrl, label: 'Código postal')),
                  const SizedBox(width: 12),
                  Expanded(child: _FormField(controller: _latCtrl, label: 'Latitud', keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _FormField(controller: _lngCtrl, label: 'Longitud', keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('Activa', style: TextStyle(color: OmniGymColors.textPrimary, fontSize: 13)),
                  const Spacer(),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeColor: OmniGymColors.primary,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: OmniGymColors.errorRed, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: OmniGymColors.textSecondary),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEdit ? 'Guardar cambios' : 'Crear sucursal'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Widgets de formulario ────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({required this.controller, required this.label, this.keyboardType});
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: OmniGymColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _FormDropdown<T> extends StatelessWidget {
  const _FormDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: OmniGymColors.card,
      style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: OmniGymColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

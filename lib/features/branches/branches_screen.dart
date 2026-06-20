import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/branch.dart';
import '../../core/providers/providers.dart';
import '../../core/services/worker_service.dart';
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onAdd: () => _openForm(context, ref, null)),
          Expanded(
            child: branchesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
      ),
      child: Row(
        children: [
          if (context.isMobile) const DrawerMenuButton(),
          Text(
            'Sucursales',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: context.isMobile
                ? const Text('Nueva')
                : const Text('Nueva sucursal'),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        Icon(icon, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
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
    final color = isActive ? OmniGymColors.success : Theme.of(context).colorScheme.onSurfaceVariant;
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
      icon: Icon(Icons.more_vert, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          tileProvider: CancellableNetworkTileProvider(),
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 30,
              height: 30,
              child: Icon(Icons.location_pin, color: Theme.of(context).colorScheme.primary, size: 30),
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
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant, size: 28),
          const SizedBox(height: 4),
          Text(
            'Sin ubicación',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
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
          Icon(Icons.store_outlined,
              size: 52, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Aún no hay sucursales',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Crea la primera sucursal de tu gimnasio.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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
  final _coloniaCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  String? _state;
  String? _municipality;
  String? _ciudad;
  BranchLocation? _selectedLocation;
  PostalLookup? _postalLookup;
  bool _postalLoading = false;
  bool _isManualMode = false;
  List<String> _colonias = [];
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  List<GeocodeResult> _searchResults = [];
  bool _searchLoading = false;
  Timer? _searchDebounce;

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
      _coloniaCtrl.text = b.address?.colonia ?? '';
      _selectedLocation = b.location;
      _isManualMode = b.address != null &&
          (b.address!.state.isNotEmpty || b.address!.municipality != null) &&
          b.address!.postalCode.isEmpty;
      if (_postalCtrl.text.length == 5) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _lookupCp(_postalCtrl.text));
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _streetCtrl.dispose();
    _postalCtrl.dispose();
    _coloniaCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _lookupCp(String cp) async {
    if (!RegExp(r'^\d{5}$').hasMatch(cp)) {
      setState(() {
        _postalLookup = null;
        _isManualMode = false;
        _colonias = [];
      });
      return;
    }
    setState(() => _postalLoading = true);
    final r = await WorkerService.lookupPostalCode(cp);
    if (!mounted) return;
    setState(() {
      _postalLoading = false;
      if (r != null) {
        _postalLookup = r;
        _isManualMode = false;
        _state = r.estado;
        _municipality = r.municipio;
        _ciudad = r.ciudad;
        _colonias = r.colonias;
      } else {
        _postalLookup = null;
        _isManualMode = true;
        _colonias = [];
      }
    });
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    if (val.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _searchLoading = true);
      final results = await WorkerService.searchAddress(val.trim());
      if (!mounted) return;
      setState(() {
        _searchLoading = false;
        _searchResults = results;
      });
    });
  }

  void _selectSearchResult(GeocodeResult r) {
    _searchCtrl.text = r.displayName;
    setState(() {
      _searchResults = [];
      _selectedLocation = BranchLocation(
        latitude: r.lat,
        longitude: r.lng,
      );
    });
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedLocation = BranchLocation(
        latitude: point.latitude,
        longitude: point.longitude,
      );
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }
    final cp = _postalCtrl.text.trim();
    if (cp.isNotEmpty && cp.length != 5) {
      setState(() => _error = 'El código postal debe tener 5 dígitos.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull ??
          await ref.read(activeTenantIdFutureProvider.future);
      if (tenantId == null) throw Exception('Tenant no encontrado.');

      BranchAddress? address;
      if (_streetCtrl.text.trim().isNotEmpty || _state != null) {
        address = BranchAddress(
          street: _streetCtrl.text.trim(),
          city: _ciudad ?? _municipality ?? _state ?? '',
          state: _state ?? '',
          postalCode: cp,
          municipality: _municipality,
          colonia: _coloniaCtrl.text.trim().isEmpty
              ? null
              : _coloniaCtrl.text.trim(),
        );
      }

      final repo = ref.read(branchRepositoryProvider);

      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          isActive: _isActive,
          address: address,
          location: _selectedLocation,
        );
        await repo.update(updated);
      } else {
        final branch = Branch(
          id: '',
          tenantId: tenantId,
          name: _nameCtrl.text.trim(),
          isActive: _isActive,
          address: address,
          location: _selectedLocation,
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _FormField(
                    controller: _nameCtrl,
                    label: 'Nombre de la sucursal'),
                const SizedBox(height: 14),
                _buildPostalField(),
                if (_postalLookup != null) ...[
                  const SizedBox(height: 14),
                  _buildSepomexConfirmation(),
                  const SizedBox(height: 14),
                  _buildColoniaField(),
                ] else if (_isManualMode) ...[
                  const SizedBox(height: 14),
                  _buildManualAddressFields(),
                ],
                const SizedBox(height: 14),
                _FormField(
                    controller: _streetCtrl, label: 'Dirección / Calle'),
                const SizedBox(height: 14),
                _buildSearchField(),
                if (_searchResults.isNotEmpty) _buildSearchResults(),
                const SizedBox(height: 12),
                _buildLocationMap(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Activa',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurface,
                            fontSize: 13)),
                    const Spacer(),
                    Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeThumbColor:
                          Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary),
                            )
                          : Text(_isEdit
                              ? 'Guardar cambios'
                              : 'Crear sucursal'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          _isEdit ? 'Editar sucursal' : 'Nueva sucursal',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18),
        ),
      ],
    );
  }

  Widget _buildPostalField() {
    return _FormField(
      controller: _postalCtrl,
      label: 'Código postal',
      keyboardType: TextInputType.number,
      maxLength: 5,
      onChanged: (v) => _lookupCp(v.trim()),
      suffixIcon: _postalLoading
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          : null,
    );
  }

  Widget _buildSepomexConfirmation() {
    final p = _postalLookup!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [p.municipio, p.estado, p.ciudad]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' · '),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColoniaField() {
    if (_colonias.isEmpty) {
      return _FormField(controller: _coloniaCtrl, label: 'Colonia');
    }
    final current = _coloniaCtrl.text.trim();
    final options = <String>{
      ..._colonias,
      if (current.isNotEmpty) current,
    }.toList();
    return _FormDropdown<String>(
      label: 'Colonia',
      value: current.isEmpty ? null : current,
      items: options
          .map((c) =>
              DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: (v) =>
          setState(() => _coloniaCtrl.text = v ?? ''),
    );
  }

  Widget _buildManualAddressFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CP no encontrado en catálogo. Completa manualmente:',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11),
        ),
        const SizedBox(height: 8),
        _FormDropdown<String>(
          label: 'Estado',
          value: _state,
          items: MexicoData.states
              .map((s) => DropdownMenuItem(
                  value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() {
            _state = v;
            _municipality = null;
          }),
        ),
        const SizedBox(height: 12),
        _FormField(
            controller: TextEditingController(text: _municipality ?? ''),
            label: 'Municipio',
            onChanged: (v) => setState(() => _municipality = v)),
        const SizedBox(height: 12),
        _FormField(controller: _coloniaCtrl, label: 'Colonia'),
      ],
    );
  }

  Widget _buildSearchField() {
    return _FormField(
      controller: _searchCtrl,
      label: 'Buscar calle o colonia (opcional)',
      suffixIcon: _searchLoading
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          : (_searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchResults = []);
                  },
                )
              : null),
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context).dividerTheme.color ??
                OmniGymColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _searchResults
            .map((r) => InkWell(
                  onTap: () => _selectSearchResult(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.displayName,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface,
                                fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildLocationMap() {
    final center = _selectedLocation != null
        ? LatLng(
            _selectedLocation!.latitude, _selectedLocation!.longitude)
        : const LatLng(23.6345, -102.5528); // centro México
    final zoom = _selectedLocation != null ? 16.0 : 5.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedLocation != null
              ? 'Toca el mapa para reubicar'
              : 'Toca el mapa para agregar ubicación',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                onTap: (_, point) => _onMapTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.omnigym.app',
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                if (_selectedLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                            _selectedLocation!.latitude,
                            _selectedLocation!.longitude),
                        width: 30,
                        height: 30,
                        child: Icon(Icons.location_pin,
                            color: Theme.of(context).colorScheme.primary,
                            size: 30),
                      ),
                    ],
                  ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors',
                        onTap: () {}),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_selectedLocation != null) ...[
          const SizedBox(height: 4),
          Text(
            '${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
            style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10),
          ),
        ],
      ],
    );
  }
}

// ─── Widgets de formulario ────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.onChanged,
    this.suffixIcon,
    this.maxLength,
    this.errorText,
    this.textCapitalization,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final int? maxLength;
  final String? errorText;
  final TextCapitalization? textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization ?? TextCapitalization.none,
      maxLength: maxLength,
      onChanged: onChanged,
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: Theme.of(context).dividerTheme.color ??
                    OmniGymColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: Theme.of(context).dividerTheme.color ??
                    OmniGymColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        errorText: errorText,
        suffixIcon: suffixIcon,
        counterText: '',
      ),
    );
  }
}

class _FormDropdown<T> extends StatelessWidget {
  const _FormDropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor:
          Theme.of(context).colorScheme.surfaceContainerHighest,
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: Theme.of(context).dividerTheme.color ??
                    OmniGymColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: Theme.of(context).dividerTheme.color ??
                    OmniGymColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

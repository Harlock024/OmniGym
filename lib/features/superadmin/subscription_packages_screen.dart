import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/providers/providers.dart';
import '../../core/services/worker_service.dart';

// ─── Modelo ligero ──────────────────────────────────────────────────────────

class SubscriptionPackage {
  const SubscriptionPackage({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.active,
    required this.stripePriceId,
    this.branches,
    this.checkins,
    this.staff,
  });

  final String id;
  final String name;
  final double price;
  final String currency;
  final bool active;
  final String stripePriceId;
  final int? branches;
  final int? checkins;
  final int? staff;

  factory SubscriptionPackage.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return SubscriptionPackage(
      id: d.id,
      name: (m['name'] ?? '') as String,
      price: ((m['price'] ?? 0) as num).toDouble(),
      currency: (m['currency'] ?? 'mxn') as String,
      active: (m['active'] ?? true) as bool,
      stripePriceId: (m['stripe_price_id'] ?? '') as String,
      branches: (m['limit_branches'] as num?)?.toInt(),
      checkins: (m['limit_checkins'] as num?)?.toInt(),
      staff: (m['limit_staff'] as num?)?.toInt(),
    );
  }
}

final subscriptionPackagesProvider =
    StreamProvider<List<SubscriptionPackage>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('subscription_packages')
      .orderBy('created_at', descending: true)
      .snapshots()
      .map((s) => s.docs.map(SubscriptionPackage.fromDoc).toList());
});

// ─── Pantalla ─────────────────────────────────────────────────────────────────

class SubscriptionPackagesScreen extends ConsumerWidget {
  const SubscriptionPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(subscriptionPackagesProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      appBar: AppBar(
        leading: context.isMobile ? const DrawerMenuButton() : null,
        automaticallyImplyLeading: false,
        title: const Text('Paquetes de suscripción'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo paquete'),
      ),
      body: packagesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (packages) {
          if (packages.isEmpty) {
            return const Center(
              child: Text('No hay paquetes. Crea el primero con "Nuevo paquete".',
                  style: TextStyle(color: OmniGymColors.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: packages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _PackageCard(pkg: packages[i]),
          );
        },
      ),
    );
  }

  void _openDialog(BuildContext context, {SubscriptionPackage? pkg}) {
    showDialog(context: context, builder: (_) => _PackageDialog(pkg: pkg));
  }
}

class _PackageCard extends ConsumerWidget {
  const _PackageCard({required this.pkg});
  final SubscriptionPackage pkg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = <String>[
      if (pkg.branches != null) '${pkg.branches} sucursales',
      if (pkg.checkins != null) '${pkg.checkins} check-ins',
      if (pkg.staff != null) '${pkg.staff} staff',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(pkg.name,
                        style: const TextStyle(
                            color: OmniGymColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    _StatusChip(active: pkg.active),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${pkg.price.toStringAsFixed(2)} ${pkg.currency.toUpperCase()} / mes',
                  style: const TextStyle(
                      color: OmniGymColors.primary, fontWeight: FontWeight.w600),
                ),
                if (limits.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(limits,
                      style: const TextStyle(
                          color: OmniGymColors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined,
                color: OmniGymColors.textSecondary, size: 20),
            onPressed: () => showDialog(
                context: context, builder: (_) => _PackageDialog(pkg: pkg)),
          ),
          IconButton(
            tooltip: pkg.active ? 'Archivar' : 'Activar',
            icon: Icon(pkg.active ? Icons.archive_outlined : Icons.unarchive_outlined,
                color: OmniGymColors.textSecondary, size: 20),
            onPressed: () => _toggleActive(context),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await WorkerService.updatePackage(id: pkg.id, active: !pkg.active);
      messenger.showSnackBar(SnackBar(
          content: Text(pkg.active ? 'Paquete archivado.' : 'Paquete activado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? OmniGymColors.primary.withAlpha(40)
            : OmniGymColors.textSecondary.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        active ? 'Activo' : 'Archivado',
        style: TextStyle(
          fontSize: 11,
          color: active ? OmniGymColors.primary : OmniGymColors.textSecondary,
        ),
      ),
    );
  }
}

// ─── Diálogo crear / editar ─────────────────────────────────────────────────

class _PackageDialog extends ConsumerStatefulWidget {
  const _PackageDialog({this.pkg});
  final SubscriptionPackage? pkg;

  @override
  ConsumerState<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends ConsumerState<_PackageDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _branchesCtrl;
  late final TextEditingController _checkinsCtrl;
  late final TextEditingController _staffCtrl;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.pkg != null;

  @override
  void initState() {
    super.initState();
    final p = widget.pkg;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(text: p != null ? p.price.toString() : '');
    _branchesCtrl = TextEditingController(text: p?.branches?.toString() ?? '');
    _checkinsCtrl = TextEditingController(text: p?.checkins?.toString() ?? '');
    _staffCtrl = TextEditingController(text: p?.staff?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _priceCtrl, _branchesCtrl, _checkinsCtrl, _staffCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final name = _nameCtrl.text.trim();
      final price = double.parse(_priceCtrl.text.trim());
      final branches = int.tryParse(_branchesCtrl.text.trim());
      final checkins = int.tryParse(_checkinsCtrl.text.trim());
      final staff = int.tryParse(_staffCtrl.text.trim());

      if (_isEdit) {
        await WorkerService.updatePackage(
          id: widget.pkg!.id,
          name: name,
          price: price,
          branches: branches,
          checkins: checkins,
          staff: staff,
        );
      } else {
        await WorkerService.createPackage(
          name: name,
          price: price,
          branches: branches,
          checkins: checkins,
          staff: staff,
        );
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_isEdit ? 'Editar paquete' : 'Nuevo paquete',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nombre del paquete', border: OutlineInputBorder()),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Precio mensual (MXN)',
                      prefixText: '\$ ',
                      border: OutlineInputBorder()),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim());
                    if (d == null || d <= 0) return 'Precio inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                const Text('Límites (opcionales)',
                    style: TextStyle(
                        color: OmniGymColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numField(_branchesCtrl, 'Sucursales')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(_checkinsCtrl, 'Check-ins')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(_staffCtrl, 'Staff')),
                  ],
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Cambiar el precio crea un nuevo precio en Stripe y archiva el anterior.',
                    style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 11),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isEdit ? 'Guardar' : 'Crear'),
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

  Widget _numField(TextEditingController c, String label) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()),
    );
  }
}

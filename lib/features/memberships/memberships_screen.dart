import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/member.dart';
import '../../core/models/membership_plan.dart';
import '../../core/models/payment.dart';
import '../../core/providers/providers.dart';
import 'facturar_dialog.dart';

class MembershipsScreen extends ConsumerStatefulWidget {
  const MembershipsScreen({super.key});

  @override
  ConsumerState<MembershipsScreen> createState() => _MembershipsScreenState();
}

class _MembershipsScreenState extends ConsumerState<MembershipsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(activeTenantIdFutureProvider);
    final tenantId = tenantAsync.valueOrNull ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, tenantId),
          _buildTabBar(),
          Expanded(
            child: tenantId.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _PlanesTab(tenantId: tenantId),
                      _PagosTab(tenantId: tenantId),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String tenantId) {
    final isMobile = context.isMobile;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isMobile) const DrawerMenuButton(),
              Text(
                'Membresías',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _tabs.index == 0
                  ? FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nuevo plan'),
                      onPressed: tenantId.isEmpty
                          ? null
                          : () => _showPlanForm(context, tenantId, null),
                    )
                  : FilledButton.icon(
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Registrar pago'),
                      onPressed: tenantId.isEmpty
                          ? null
                          : () => _showRegisterPayment(context, tenantId),
                    ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: TabBar(
        controller: _tabs,
        onTap: (_) => setState(() {}),
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: const [
          Tab(text: 'Planes'),
          Tab(text: 'Pagos'),
        ],
      ),
    );
  }

  void _showPlanForm(
      BuildContext context, String tenantId, MembershipPlan? plan) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlanFormDialog(tenantId: tenantId, existing: plan),
    );
  }

  void _showRegisterPayment(BuildContext context, String tenantId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RegisterPaymentDialog(tenantId: tenantId),
    );
  }
}

// ─── Tab Planes ───────────────────────────────────────────────────────────────

class _PlanesTab extends ConsumerWidget {
  const _PlanesTab({required this.tenantId});
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(allPlansProvider(tenantId));

    return plansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      data: (plans) {
        if (plans.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.card_membership,
                    size: 52, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Sin planes de membresía',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Crea el primer plan para tus socios.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: 180,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: plans.length,
          itemBuilder: (ctx, i) =>
              _PlanCard(plan: plans[i], tenantId: tenantId),
        );
      },
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.tenantId});
  final MembershipPlan plan;
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = plan.isActive;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Theme.of(context).dividerTheme.color ?? OmniGymColors.border : Theme.of(context).dividerTheme.color ?? OmniGymColors.border.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _PlanMenu(plan: plan, tenantId: tenantId),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '\$${plan.price.toStringAsFixed(plan.price % 1 == 0 ? 0 : 2)} MXN',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.schedule,
                  size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                _durationLabel(plan.durationDays),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
              const Spacer(),
              if (!isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Inactivo',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _durationLabel(int days) {
    if (days == 30) return '1 mes';
    if (days == 60) return '2 meses';
    if (days == 90) return '3 meses';
    if (days == 180) return '6 meses';
    if (days == 365) return '1 año';
    if (days % 30 == 0) return '${days ~/ 30} meses';
    return '$days días';
  }
}

class _PlanMenu extends ConsumerWidget {
  const _PlanMenu({required this.plan, required this.tenantId});
  final MembershipPlan plan;
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 16),
            SizedBox(width: 8),
            Text('Editar'),
          ]),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(children: [
            Icon(
              plan.isActive
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(plan.isActive ? 'Desactivar' : 'Activar'),
          ]),
        ),
      ],
      onSelected: (action) async {
        if (action == 'edit') {
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  _PlanFormDialog(tenantId: tenantId, existing: plan),
            );
          }
        } else if (action == 'toggle') {
          await ref.read(planRepositoryProvider).setActive(
                tenantId,
                plan.id,
                isActive: !plan.isActive,
              );
        }
      },
    );
  }
}

// ─── Tab Pagos ────────────────────────────────────────────────────────────────

class _PagosTab extends ConsumerWidget {
  const _PagosTab({required this.tenantId});
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(tenantPaymentsProvider(tenantId));

    return paymentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      data: (payments) {
        if (payments.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long,
                    size: 52, color: Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(height: 12),
                Text(
                  'Sin pagos registrados',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'Registra el primer pago de membresía.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Header de tabla
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('Socio',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('Plan',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('Monto',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(width: 16),
                  SizedBox(
                    width: 110,
                    child: Text('Fecha',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: payments.length,
                itemBuilder: (_, i) => _PaymentRow(payment: payments[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final dt = payment.createdAt;
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (payment.memberName ?? '?')[0].toUpperCase(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    payment.memberName ?? '—',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              payment.planName ?? '—',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '\$${payment.amount.toStringAsFixed(payment.amount % 1 == 0 ? 0 : 2)}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: OmniGymColors.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 110,
            child: Text(
              dateStr,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Formulario de plan ───────────────────────────────────────────────────────

class _PlanFormDialog extends ConsumerStatefulWidget {
  const _PlanFormDialog({required this.tenantId, this.existing});
  final String tenantId;
  final MembershipPlan? existing;

  @override
  ConsumerState<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends ConsumerState<_PlanFormDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  static const _durationPresets = [
    (label: '15 días', days: 15),
    (label: '1 mes', days: 30),
    (label: '2 meses', days: 60),
    (label: '3 meses', days: 90),
    (label: '6 meses', days: 180),
    (label: '1 año', days: 365),
  ];

  int? _selectedDays;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _nameCtrl.text = p.name;
      _priceCtrl.text =
          p.price % 1 == 0 ? p.price.toInt().toString() : p.price.toString();
      _daysCtrl.text = p.durationDays.toString();
      _selectedDays = _durationPresets.any((e) => e.days == p.durationDays)
          ? p.durationDays
          : null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final days = int.tryParse(_daysCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Ingresa un precio válido.');
      return;
    }
    if (days == null || days <= 0) {
      setState(() => _error = 'Ingresa una duración válida.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(planRepositoryProvider);
      if (_isEdit) {
        await repo.update(widget.existing!.copyWith(
          name: name,
          price: price,
          durationDays: days,
        ));
      } else {
        await repo.create(MembershipPlan(
          id: '',
          tenantId: widget.tenantId,
          name: name,
          price: price,
          durationDays: days,
        ));
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
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _isEdit ? 'Editar plan' : 'Nuevo plan',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close,
                        color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Field(controller: _nameCtrl, label: 'Nombre del plan'),
              const SizedBox(height: 14),
              _Field(
                controller: _priceCtrl,
                label: 'Precio (MXN)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                ],
                prefix: Text('\$  ',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              ),
              const SizedBox(height: 14),
              // Presets de duración
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _durationPresets.map((p) {
                  final selected = _selectedDays == p.days;
                  return ChoiceChip(
                    label: Text(p.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedDays = p.days;
                        _daysCtrl.text = p.days.toString();
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              _Field(
                controller: _daysCtrl,
                label: 'Duración (días)',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _selectedDays = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
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
                                strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                        : Text(_isEdit ? 'Guardar' : 'Crear plan'),
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

// ─── Registrar pago ───────────────────────────────────────────────────────────

class _RegisterPaymentDialog extends ConsumerStatefulWidget {
  const _RegisterPaymentDialog({required this.tenantId, this.preselectedMember});
  final String tenantId;
  final Member? preselectedMember;

  @override
  ConsumerState<_RegisterPaymentDialog> createState() =>
      _RegisterPaymentDialogState();
}

class _RegisterPaymentDialogState
    extends ConsumerState<_RegisterPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  Member? _selectedMember;
  MembershipPlan? _selectedPlan;
  bool _saving = false;
  String? _error;
  String _memberSearch = '';

  @override
  void initState() {
    super.initState();
    if (widget.preselectedMember != null) {
      _selectedMember = widget.preselectedMember;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPlanSelected(MembershipPlan? plan) {
    setState(() {
      _selectedPlan = plan;
      if (plan != null) {
        _amountCtrl.text = plan.price % 1 == 0
            ? plan.price.toInt().toString()
            : plan.price.toString();
      }
    });
  }

  Future<void> _save() async {
    if (_selectedMember == null) {
      setState(() => _error = 'Selecciona un socio.');
      return;
    }
    if (_selectedPlan == null) {
      setState(() => _error = 'Selecciona un plan.');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresa un monto válido.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final branchId = ref.read(activeTenantIdFutureProvider).valueOrNull ?? '';
      final currentBranchId =
          ref.read(currentBranchIdProvider).valueOrNull ?? branchId;

      final pagoId = await ref.read(paymentRepositoryProvider).registerPayment(
            tenantId: widget.tenantId,
            branchId: currentBranchId.isNotEmpty
                ? currentBranchId
                : (_selectedMember!.allowedBranches.isNotEmpty
                    ? _selectedMember!.allowedBranches.first
                    : ''),
            memberId: _selectedMember!.id,
            memberName: _selectedMember!.name,
            planId: _selectedPlan!.id,
            planName: _selectedPlan!.name,
            durationDays: _selectedPlan!.durationDays,
            amount: amount,
            reference: _referenceCtrl.text.trim().isEmpty
                ? null
                : _referenceCtrl.text.trim(),
          );

      if (mounted) {
        Navigator.pop(context);
        _mostrarDialogoFacturar(
            context, ref, widget.tenantId, pagoId,
            _selectedMember!, _selectedPlan!, amount);
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _mostrarDialogoFacturar(BuildContext context, WidgetRef ref,
      String tenantId, String paymentId, Member member, MembershipPlan plan, double amount) {
    showDialog(
      context: context,
      builder: (ctx) => FacturarDialog(
        tenantId: tenantId,
        paymentId: paymentId,
        member: member,
        plan: plan,
        amount: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider(widget.tenantId));
    final plansAsync = ref.watch(allPlansProvider(widget.tenantId));

    final members = membersAsync.valueOrNull ?? [];
    final filtered = _memberSearch.isEmpty
        ? members
        : members
            .where((m) =>
                m.name.toLowerCase().contains(_memberSearch.toLowerCase()) ||
                m.email.toLowerCase().contains(_memberSearch.toLowerCase()))
            .toList();
    final plans = (plansAsync.valueOrNull ?? [])
        .where((p) => p.isActive)
        .toList();

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Registrar pago',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close,
                        color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Selección de socio ──────────────────────────────────────
              if (_selectedMember == null) ...[
                _Field(
                  controller: _searchCtrl,
                  label: 'Buscar socio',
                  prefix: Icon(Icons.search,
                      size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onChanged: (v) => setState(() => _memberSearch = v),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
                  ),
                  child: membersAsync.isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : filtered.isEmpty
                          ? Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Sin resultados',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 13)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final m = filtered[i];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary.withAlpha(30),
                                    child: Text(
                                      m.name[0].toUpperCase(),
                                      style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(m.name,
                                      style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontSize: 13)),
                                  subtitle: Text(m.email,
                                      style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 11)),
                                  onTap: () => setState(() {
                                    _selectedMember = m;
                                    _searchCtrl.clear();
                                    _memberSearch = '';
                                  }),
                                );
                              },
                            ),
                ),
              ] else ...[
                // Socio seleccionado
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(40),
                        child: Text(
                          _selectedMember!.name[0].toUpperCase(),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedMember!.name,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(_selectedMember!.email,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () =>
                            setState(() => _selectedMember = null),
                        constraints: const BoxConstraints(
                            minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ── Plan ──────────────────────────────────────────────────
              DropdownButtonFormField<MembershipPlan>(
                initialValue: _selectedPlan,
                isExpanded: true,
                menuMaxHeight: 280,
                hint: Text('Seleccionar plan',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                items: plans
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name} — \$${p.price % 1 == 0 ? p.price.toInt() : p.price} · ${p.durationDays}d',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: _onPlanSelected,
                dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                decoration: InputDecoration(
                  labelText: 'Plan',
                  labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Theme.of(context).colorScheme.primary)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // ── Monto ─────────────────────────────────────────────────
              _Field(
                controller: _amountCtrl,
                label: 'Monto cobrado (MXN)',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'))
                ],
                prefix: Text('\$  ',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              ),
              const SizedBox(height: 14),

              // ── Referencia ────────────────────────────────────────────
              _Field(
                  controller: _referenceCtrl,
                  label: 'Referencia / Folio (opcional)'),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                        : const Text('Confirmar pago'),
                    onPressed: _saving ? null : _save,
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

// ─── Widgets comunes ──────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
    this.prefix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        prefix: prefix,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ─── API pública para abrir el dialog desde otras pantallas ──────────────────

class RegisterPaymentFromMember extends StatelessWidget {
  const RegisterPaymentFromMember({
    super.key,
    required this.tenantId,
    required this.member,
  });

  final String tenantId;
  final Member member;

  @override
  Widget build(BuildContext context) {
    return _RegisterPaymentDialog(
      tenantId: tenantId,
      preselectedMember: member,
    );
  }
}

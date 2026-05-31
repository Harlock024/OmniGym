import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/branch.dart';
import '../../core/models/member.dart';
import '../../core/providers/providers.dart';
import '../memberships/memberships_screen.dart' show RegisterPaymentFromMember;
import 'member_detail_dialog.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _allMembersProvider = StreamProvider<List<Member>>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  if (tenantId == null) { yield []; return; }
  yield* ref.watch(memberRepositoryProvider).watchAll(tenantId);
});

final _allBranchesForMembersProvider = StreamProvider<List<Branch>>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  if (tenantId == null) { yield []; return; }
  yield* ref.watch(branchRepositoryProvider).watchAll(tenantId);
});

final _memberSearchProvider = StateProvider<String>((ref) => '');
final _memberStatusFilterProvider = StateProvider<AccessStatus?>((ref) => null);
final _memberBranchFilterProvider = StateProvider<String?>((ref) => null);

final _filteredMembersProvider = Provider<AsyncValue<List<Member>>>((ref) {
  return ref.watch(_allMembersProvider).whenData((members) {
    final q = ref.watch(_memberSearchProvider).toLowerCase();
    final status = ref.watch(_memberStatusFilterProvider);
    final branchId = ref.watch(_memberBranchFilterProvider);

    return members.where((m) {
      if (q.isNotEmpty &&
          !m.name.toLowerCase().contains(q) &&
          !m.email.toLowerCase().contains(q)) return false;
      if (status != null && m.accessStatus != status) return false;
      if (branchId != null && !m.allowedBranches.contains(branchId)) return false;
      return true;
    }).toList();
  });
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(_filteredMembersProvider);
    final branches = ref.watch(_allBranchesForMembersProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onAdd: () => _openForm(context, ref, null, branches)),
          _Filters(branches: branches),
          // Column headers (hidden on mobile)
          if (!context.isMobile) _ColumnHeaders(),
          Expanded(
            child: membersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: OmniGymColors.textSecondary)),
              ),
              data: (members) => members.isEmpty
                  ? const _EmptyState()
                  : _MemberList(members: members, branches: branches),
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref, Member? member, List<Branch> branches) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MemberFormDialog(existing: member, branches: branches),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(_allMembersProvider).valueOrNull?.length ?? 0;
    final isMobile = context.isMobile;

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Socios',
          style: TextStyle(
            color: OmniGymColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '$total registrados',
          style: const TextStyle(
              color: OmniGymColors.textSecondary, fontSize: 12),
        ),
      ],
    );

    final searchField = SizedBox(
      height: 38,
      child: TextField(
        onChanged: (v) =>
            ref.read(_memberSearchProvider.notifier).state = v,
        style: const TextStyle(
            color: OmniGymColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar socio...',
          hintStyle: const TextStyle(
              color: OmniGymColors.textSecondary, fontSize: 13),
          prefixIcon: const Icon(Icons.search,
              size: 16, color: OmniGymColors.textSecondary),
          filled: true,
          fillColor: OmniGymColors.surface,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: OmniGymColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: OmniGymColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: OmniGymColors.primary)),
        ),
      ),
    );

    final addButton = FilledButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.person_add_outlined, size: 16),
      label: isMobile ? const Text('Nuevo') : const Text('Nuevo socio'),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OmniGymColors.border)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const DrawerMenuButton(),
                    Expanded(child: titleColumn),
                    addButton,
                  ],
                ),
                const SizedBox(height: 10),
                searchField,
              ],
            )
          : Row(
              children: [
                titleColumn,
                const SizedBox(width: 16),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: searchField,
                  ),
                ),
                const SizedBox(width: 12),
                addButton,
              ],
            ),
    );
  }
}

// ─── Filtros ──────────────────────────────────────────────────────────────────

class _Filters extends ConsumerWidget {
  const _Filters({required this.branches});
  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilter = ref.watch(_memberStatusFilterProvider);
    final branchFilter = ref.watch(_memberBranchFilterProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OmniGymColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Activos'),
              selected: statusFilter == AccessStatus.active,
              onSelected: (v) => ref.read(_memberStatusFilterProvider.notifier).state =
                  v ? AccessStatus.active : null,
            ),
            FilterChip(
              label: const Text('Suspendidos'),
              selected: statusFilter == AccessStatus.suspended,
              onSelected: (v) => ref.read(_memberStatusFilterProvider.notifier).state =
                  v ? AccessStatus.suspended : null,
            ),
            if (branches.isNotEmpty) ...[
              const VerticalDivider(width: 16),
              ...branches.map((b) => FilterChip(
                    label: Text(b.name),
                    selected: branchFilter == b.id,
                    onSelected: (v) => ref
                        .read(_memberBranchFilterProvider.notifier)
                        .state = v ? b.id : null,
                  )),
            ],
          ],
        ),
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
          Expanded(flex: 2, child: Text('VENCIMIENTO', style: style)),
          SizedBox(width: 100, child: Text('ESTADO', style: style)),
          SizedBox(width: 60, child: Text('ACCIONES', style: style)),
        ],
      ),
    );
  }
}

// ─── Lista de socios ─────────────────────────────────────────────────────────

class _MemberList extends ConsumerWidget {
  const _MemberList({required this.members, required this.branches});
  final List<Member> members;
  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: members.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: OmniGymColors.border),
      itemBuilder: (context, i) => _MemberRow(
        member: members[i],
        branches: branches,
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member, required this.branches});
  final Member member;
  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = member.accessStatus == AccessStatus.active;
    final isExpired = member.expirationDate.isBefore(DateTime.now());
    final daysLeft = member.expirationDate.difference(DateTime.now()).inDays;

    Future<void> openDetail() async {
      final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull ??
          await ref.read(activeTenantIdFutureProvider.future);
      if (tenantId != null && context.mounted) {
        showDialog(
          context: context,
          builder: (_) => MemberDetailDialog(member: member, tenantId: tenantId),
        );
      }
    }

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor:
          isActive ? OmniGymColors.primary.withAlpha(40) : OmniGymColors.border,
      backgroundImage:
          member.photoUrl != null ? NetworkImage(member.photoUrl!) : null,
      child: member.photoUrl == null
          ? Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: isActive
                    ? OmniGymColors.primary
                    : OmniGymColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );

    if (context.isMobile) {
      // Card layout for mobile
      return InkWell(
        onTap: openDetail,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.name,
                            style: const TextStyle(
                                color: OmniGymColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: member.accessStatus),
                      ],
                    ),
                    Text(
                      member.email,
                      style: const TextStyle(
                          color: OmniGymColors.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Text(
                          _formatDate(member.expirationDate),
                          style: TextStyle(
                            color: isExpired
                                ? OmniGymColors.errorRed
                                : OmniGymColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (!isExpired && daysLeft <= 7) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· vence en $daysLeft días',
                            style: const TextStyle(
                                color: Colors.orange, fontSize: 11),
                          ),
                        ] else if (isExpired) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '· vencida',
                            style: TextStyle(
                                color: OmniGymColors.errorRed, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _MemberActions(member: member, branches: branches),
            ],
          ),
        ),
      );
    }

    // Table row layout for desktop/tablet
    return InkWell(
      onTap: openDetail,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                              color: OmniGymColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (member.phone != null)
                          Text(
                            member.phone!,
                            style: const TextStyle(
                                color: OmniGymColors.textSecondary,
                                fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                member.email,
                style: const TextStyle(
                    color: OmniGymColors.textSecondary, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(member.expirationDate),
                    style: TextStyle(
                      color: isExpired
                          ? OmniGymColors.errorRed
                          : OmniGymColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  if (!isExpired && daysLeft <= 7)
                    Text(
                      'Vence en $daysLeft días',
                      style: const TextStyle(
                          color: Colors.orange, fontSize: 11),
                    )
                  else if (isExpired)
                    const Text(
                      'Vencida',
                      style: TextStyle(
                          color: OmniGymColors.errorRed, fontSize: 11),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: _StatusBadge(status: member.accessStatus),
            ),
            SizedBox(
              width: 60,
              child: _MemberActions(member: member, branches: branches),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AccessStatus status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == AccessStatus.active;
    final color = isActive ? OmniGymColors.success : OmniGymColors.errorRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        isActive ? 'Activo' : 'Suspendido',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MemberActions extends ConsumerWidget {
  const _MemberActions({required this.member, required this.branches});
  final Member member;
  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = member.accessStatus == AccessStatus.active;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16, color: OmniGymColors.textSecondary),
      color: OmniGymColors.card,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: const Row(children: [
            Icon(Icons.edit_outlined, size: 15),
            SizedBox(width: 8),
            Text('Editar'),
          ]),
        ),
        PopupMenuItem(
          value: 'qr',
          child: const Row(children: [
            Icon(Icons.qr_code, size: 15),
            SizedBox(width: 8),
            Text('Ver QR'),
          ]),
        ),
        const PopupMenuItem(
          value: 'payment',
          child: Row(children: [
            Icon(Icons.payment, size: 15),
            SizedBox(width: 8),
            Text('Registrar pago'),
          ]),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(children: [
            Icon(isActive ? Icons.block : Icons.check_circle_outline, size: 15),
            const SizedBox(width: 8),
            Text(isActive ? 'Suspender' : 'Reactivar'),
          ]),
        ),
      ],
      onSelected: (action) async {
        if (action == 'edit') {
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _MemberFormDialog(existing: member, branches: branches),
            );
          }
        } else if (action == 'payment') {
          if (context.mounted) {
            final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
                ?? await ref.read(activeTenantIdFutureProvider.future);
            if (tenantId != null && context.mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => RegisterPaymentFromMember(
                  tenantId: tenantId,
                  member: member,
                ),
              );
            }
          }
        } else if (action == 'qr') {
          if (context.mounted) _showQrDialog(context);
        } else if (action == 'toggle') {
          final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
              ?? await ref.read(activeTenantIdFutureProvider.future);
          if (tenantId != null) {
            final newStatus = isActive ? AccessStatus.suspended : AccessStatus.active;
            await ref
                .read(memberRepositoryProvider)
                .updateAccessStatus(tenantId, member.id, newStatus);
          }
        }
      },
    );
  }

  void _showQrDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: OmniGymColors.card,
        title: Text('QR – ${member.name}',
            style: const TextStyle(color: OmniGymColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: member.qrToken,
                version: QrVersions.auto,
                size: 180,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              member.name,
              style: const TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              member.qrToken,
              style: const TextStyle(
                color: OmniGymColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fitness_center, size: 52, color: OmniGymColors.textSecondary),
          SizedBox(height: 12),
          Text(
            'Sin socios registrados',
            style: TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'Usa el botón "Nuevo socio" para agregar el primero.',
            style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Formulario de socio ─────────────────────────────────────────────────────

class _MemberFormDialog extends ConsumerStatefulWidget {
  const _MemberFormDialog({this.existing, required this.branches});
  final Member? existing;
  final List<Branch> branches;

  @override
  ConsumerState<_MemberFormDialog> createState() => _MemberFormDialogState();
}

class _MemberFormDialogState extends ConsumerState<_MemberFormDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<String> _selectedBranches = [];
  DateTime _expirationDate = DateTime.now().add(const Duration(days: 30));
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    if (m != null) {
      _nameCtrl.text = m.name;
      _emailCtrl.text = m.email;
      _phoneCtrl.text = m.phone ?? '';
      _selectedBranches = List.from(m.allowedBranches);
      _expirationDate = m.expirationDate;
    } else if (widget.branches.isNotEmpty) {
      _selectedBranches = [widget.branches.first.id];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Nombre y correo son requeridos.');
      return;
    }
    if (_selectedBranches.isEmpty) {
      setState(() => _error = 'Selecciona al menos una sucursal.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
          ?? await ref.read(activeTenantIdFutureProvider.future);
      if (tenantId == null) throw Exception('Tenant no encontrado.');

      final repo = ref.read(memberRepositoryProvider);

      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          allowedBranches: _selectedBranches,
          expirationDate: _expirationDate,
        );
        await repo.update(tenantId, updated);
      } else {
        final qrToken = _generateToken();
        final member = Member(
          id: '',
          tenantId: tenantId,
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          accessStatus: AccessStatus.active,
          allowedBranches: _selectedBranches,
          qrToken: qrToken,
          expirationDate: _expirationDate,
        );
        await repo.create(member);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _generateToken() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'QR${now.toRadixString(36).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: OmniGymColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      _isEdit ? 'Editar socio' : 'Nuevo socio',
                      style: const TextStyle(
                        color: OmniGymColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: OmniGymColors.textSecondary, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _FormRow(children: [
                  _MemberField(
                      controller: _nameCtrl, label: 'Nombre completo'),
                  _MemberField(
                      controller: _emailCtrl,
                      label: 'Correo electrónico',
                      keyboardType: TextInputType.emailAddress),
                ]),
                const SizedBox(height: 14),
                _FormRow(children: [
                  _MemberField(
                      controller: _phoneCtrl,
                      label: 'Teléfono (opcional)',
                      keyboardType: TextInputType.phone),
                  _ExpirationPicker(
                    value: _expirationDate,
                    onChanged: (d) => setState(() => _expirationDate = d),
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('Sucursales permitidas',
                    style: TextStyle(
                        color: OmniGymColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: widget.branches.map((b) {
                    final selected = _selectedBranches.contains(b.id);
                    return FilterChip(
                      label: Text(b.name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedBranches.add(b.id);
                        } else {
                          _selectedBranches.remove(b.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: OmniGymColors.errorRed, fontSize: 12)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          foregroundColor: OmniGymColors.textSecondary),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_isEdit ? 'Guardar' : 'Crear socio'),
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
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .expand((w) => [w, const SizedBox(height: 14)])
            .toList()
          ..removeLast(),
      );
    }
    return Row(
      children: children
          .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
          .toList()
        ..removeLast(),
    );
  }
}

class _MemberField extends StatelessWidget {
  const _MemberField({required this.controller, required this.label, this.keyboardType});
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

class _ExpirationPicker extends StatelessWidget {
  const _ExpirationPicker({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final text =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
        );
        if (picked != null) onChanged(picked);
      },
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(text: text),
          style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Fecha de vencimiento',
            labelStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
            suffixIcon: const Icon(Icons.calendar_today, size: 16, color: OmniGymColors.textSecondary),
            filled: true,
            fillColor: OmniGymColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OmniGymColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ),
    );
  }
}

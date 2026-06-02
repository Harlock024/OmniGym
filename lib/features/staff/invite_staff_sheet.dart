import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_user.dart';
import '../../core/models/branch.dart';
import '../../core/providers/providers.dart';
import '../../core/services/worker_service.dart';

class InviteStaffSheet extends ConsumerStatefulWidget {
  const InviteStaffSheet({super.key});

  @override
  ConsumerState<InviteStaffSheet> createState() => _InviteStaffSheetState();
}

class _InviteStaffSheetState extends ConsumerState<InviteStaffSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  UserRole _role = UserRole.staff;
  String? _selectedBranchId;
  List<Branch> _branches = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
        ?? await ref.read(activeTenantIdFutureProvider.future);
    if (tenantId == null || !mounted) return;
    final snap = await ref
        .read(firestoreProvider)
        .collection('tenants')
        .doc(tenantId)
        .collection('branches')
        .orderBy('name')
        .get();
    if (!mounted) return;
    setState(() {
      _branches = snap.docs
          .map((d) => Branch.fromFirestore(d as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });

    try {
      final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
          ?? await ref.read(activeTenantIdFutureProvider.future);
      if (tenantId == null) throw Exception('Tenant no encontrado.');

      final branchId = _role == UserRole.staff ? _selectedBranchId : null;
      final gymName = ref.read(activeTenantProvider).valueOrNull?.name;

      // El worker crea el usuario en Auth, asigna claims, escribe /users/{uid}
      // y envía el email de invitación (Resend) — todo server-side de forma atómica.
      await WorkerService.createStaff(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        role: _role.name,
        tenantId: tenantId,
        branchId: branchId,
        gymName: gymName,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operador creado. Recibirá un correo para configurar su contraseña.'),
          ),
        );
      }
    } on StaffAlreadyExistsException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invitar operador',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requerido';
                if (!v.contains('@')) return 'Correo inválido';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Rol',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: UserRole.owner, child: Text('Owner')),
                DropdownMenuItem(value: UserRole.staff, child: Text('Staff (Recepcionista)')),
              ],
              onChanged: (v) => setState(() {
                _role = v!;
                _selectedBranchId = null;
              }),
            ),
            if (_role == UserRole.staff) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedBranchId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sucursal asignada',
                  prefixIcon: Icon(Icons.store_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _branches
                    .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedBranchId = v),
                validator: (v) =>
                    (_role == UserRole.staff && (v == null || v.isEmpty))
                        ? 'Selecciona una sucursal'
                        : null,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enviar invitación'),
            ),
          ],
        ),
      ),
    );
  }
}

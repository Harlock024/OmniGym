import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_user.dart';
import '../../core/models/branch.dart';
import '../../core/providers/providers.dart';
import '../../core/services/staff_account_service.dart';

/// Modal de invitación de operadores. Se abre con [showDialog].
class InviteStaffDialog extends ConsumerStatefulWidget {
  const InviteStaffDialog({super.key});

  @override
  ConsumerState<InviteStaffDialog> createState() => _InviteStaffDialogState();
}

class _InviteStaffDialogState extends ConsumerState<InviteStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _csdCargoCtrl = TextEditingController();

  UserRole _role = UserRole.receptionist;
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
    _csdCargoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final tenantId =
        ref.read(activeTenantIdFutureProvider).valueOrNull ??
        await ref.read(activeTenantIdFutureProvider.future);
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
          .map(
            (d) => Branch.fromFirestore(
              d as DocumentSnapshot<Map<String, dynamic>>,
            ),
          )
          .toList();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tenantId =
          ref.read(activeTenantIdFutureProvider).valueOrNull ??
          await ref.read(activeTenantIdFutureProvider.future);
      if (tenantId == null) throw Exception('Tenant no encontrado.');

      final result = await ref
          .read(staffAccountServiceProvider)
          .create(
            name: _nameCtrl.text.trim(),
            contactEmail: _emailCtrl.text.trim(),
            role: _role.name,
            tenantId: tenantId,
            branchId: _selectedBranchId!,
            csdCargo: _csdCargoCtrl.text.trim(),
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.emailSent
                  ? 'Cuenta ${result.username} creada. La invitación fue enviada al correo de contacto.'
                  : 'Cuenta ${result.username} creada, pero no se pudo enviar el correo. Reenvía la invitación desde Equipo.',
            ),
          ),
        );
      }
    } on StaffAccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo crear la cuenta. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Invitar Staff',
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
                    labelText: 'Correo de contacto',
                    helperText:
                        'Recibirá la invitación y la recuperación de acceso.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(v.trim())) {
                      return 'Correo inválido';
                    }
                    return null;
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Se generará un usuario laboral único. La cuenta se activará cuando el empleado acepte y establezca su contraseña.',
                  ),
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
                  items: [
                    if (ref.watch(currentAppUserProvider).valueOrNull?.role !=
                        UserRole.staff)
                      const DropdownMenuItem(
                        value: UserRole.staff,
                        child: Text('Staff (encargado)'),
                      ),
                    const DropdownMenuItem(
                      value: UserRole.receptionist,
                      child: Text('Recepcionista'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _role = v!;
                    _selectedBranchId = null;
                  }),
                ),
                if (_role == UserRole.staff ||
                    _role == UserRole.receptionist) ...[
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
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBranchId = v),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Selecciona una sucursal'
                        : null,
                  ),
                ],
                if (_role == UserRole.receptionist)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Comenzará sin módulos habilitados. Asigna sus accesos desde Equipo → Permisos.',
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _csdCargoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cargo de CSD (opcional)',
                    helperText: 'Para staff con acceso fiscal',
                    prefixIcon: Icon(Icons.workspace_premium_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Invitar Staff'),
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/providers/providers.dart';

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final user = ref.read(currentUserProvider);
    if (user == null || user.email == null) {
      setState(() { _error = 'No se pudo obtener el usuario.'; _loading = false; });
      return;
    }

    try {
      // Re-autenticación obligatoria antes de cambiar contraseña
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentCtrl.text,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newCtrl.text);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada correctamente.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mapError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(String code) => switch (code) {
        'wrong-password' || 'invalid-credential' =>
          'La contraseña actual es incorrecta.',
        'weak-password' => 'La nueva contraseña es muy débil (mínimo 6 caracteres).',
        'requires-recent-login' =>
          'Sesión expirada. Cierra sesión e inicia de nuevo.',
        _ => 'Error al cambiar contraseña. Intenta de nuevo.',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OmniGymColors.card,
      title: const Text('Cambiar contraseña',
          style: TextStyle(color: OmniGymColors.textPrimary)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PasswordField(
              controller: _currentCtrl,
              label: 'Contraseña actual',
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _newCtrl,
              label: 'Nueva contraseña',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requerido';
                if (v.length < 6) return 'Mínimo 6 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _confirmCtrl,
              label: 'Confirmar contraseña',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) =>
                  v != _newCtrl.text ? 'Las contraseñas no coinciden' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: OmniGymColors.errorRed, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cambiar'),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}

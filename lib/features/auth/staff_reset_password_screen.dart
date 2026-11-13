import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import 'auth_widgets.dart';

class StaffResetPasswordScreen extends ConsumerStatefulWidget {
  const StaffResetPasswordScreen({super.key, required this.code});
  final String code;
  @override
  ConsumerState<StaffResetPasswordScreen> createState() =>
      _StaffResetPasswordScreenState();
}

class _StaffResetPasswordScreenState
    extends ConsumerState<StaffResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(firebaseAuthProvider)
          .confirmPasswordReset(code: widget.code, newPassword: _password.text);
      if (mounted) setState(() => _done = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'weak-password'
              ? 'Elige una contraseña más segura.'
              : 'El enlace venció o ya fue utilizado. Solicita una nueva recuperación.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo cambiar la contraseña. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthPage(
    builder: (context) => Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthLogo(),
          const SizedBox(height: 20),
          Text(
            _done ? 'Contraseña actualizada' : 'Recuperar cuenta laboral',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (!_done) ...[
            TextFormField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Usa al menos 8 caracteres.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value != _password.text
                  ? 'Las contraseñas no coinciden.'
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AuthErrorBanner(message: _error!),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Guardando…' : 'Guardar contraseña'),
            ),
          ],
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Ir a iniciar sesión'),
          ),
        ],
      ),
    ),
  );
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import 'auth_widgets.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _checking = true;
  bool _valid = false;
  bool _retryVerification = false;
  bool _busy = false;
  bool _done = false;
  int _verification = 0;
  String? _email;
  String? _error;

  static const _invalidLink =
      'El enlace venció o ya fue utilizado. Solicita una nueva recuperación.';
  static const _invalidCodes = {
    'expired-action-code',
    'invalid-action-code',
    'user-disabled',
    'user-not-found',
  };

  @override
  void initState() {
    super.initState();
    _verify();
  }

  @override
  void didUpdateWidget(ResetPasswordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _password.clear();
      _confirmation.clear();
      _verify();
    }
  }

  Future<void> _verify() async {
    final verification = ++_verification;
    setState(() {
      _checking = true;
      _valid = false;
      _busy = false;
      _done = false;
      _retryVerification = false;
      _email = null;
      _error = null;
    });
    try {
      if (widget.code.isEmpty) {
        throw FirebaseAuthException(code: 'invalid-action-code');
      }
      final email = await ref
          .read(firebaseAuthProvider)
          .verifyPasswordResetCode(widget.code);
      if (mounted && verification == _verification) {
        setState(() {
          _email = email;
          _valid = true;
        });
      }
    } catch (error) {
      if (mounted && verification == _verification) {
        final invalid =
            error is FirebaseAuthException &&
            _invalidCodes.contains(error.code);
        setState(() {
          _retryVerification = !invalid;
          _error = invalid
              ? _invalidLink
              : 'No se pudo verificar el enlace. Intenta de nuevo.';
        });
      }
    } finally {
      if (mounted && verification == _verification) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_valid || !_form.currentState!.validate()) return;
    final verification = _verification;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(firebaseAuthProvider)
          .confirmPasswordReset(code: widget.code, newPassword: _password.text);
      if (mounted && verification == _verification) {
        setState(() => _done = true);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted && verification == _verification) {
        setState(() {
          if (_invalidCodes.contains(error.code)) {
            _valid = false;
            _error = _invalidLink;
          } else {
            _error = error.code == 'weak-password'
                ? 'Elige una contraseña más segura.'
                : 'No se pudo cambiar la contraseña. Intenta de nuevo.';
          }
        });
      }
    } catch (_) {
      if (mounted && verification == _verification) {
        setState(
          () => _error = 'No se pudo cambiar la contraseña. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted && verification == _verification) {
        setState(() => _busy = false);
      }
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
            _done ? 'Contraseña actualizada' : 'Recuperar contraseña',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_checking)
            const Center(child: CircularProgressIndicator())
          else if (_done)
            const Text(
              'Ya puedes iniciar sesión con tu nueva contraseña.',
              textAlign: TextAlign.center,
            )
          else ...[
            if (_valid) ...[
              Text('Establece una nueva contraseña para $_email.'),
              const SizedBox(height: 16),
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
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value != _password.text
                    ? 'Las contraseñas no coinciden.'
                    : null,
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AuthErrorBanner(message: _error!),
              ),
            const SizedBox(height: 20),
            if (_valid)
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Guardando…' : 'Guardar contraseña'),
              )
            else if (_retryVerification)
              FilledButton(onPressed: _verify, child: const Text('Reintentar'))
            else
              FilledButton(
                onPressed: () => context.go('/forgot-password'),
                child: const Text('Solicitar otro enlace'),
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

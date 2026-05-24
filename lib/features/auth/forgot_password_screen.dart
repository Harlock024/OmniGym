import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/providers/providers.dart';
import 'auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(firebaseAuthProvider)
          .sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mapError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(String code) => switch (code) {
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'invalid-email' => 'Correo electrónico inválido.',
        _ => 'Error al enviar el correo. Intenta de nuevo.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: AuthCard(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _sent
                ? _SentState(email: _emailCtrl.text.trim())
                : _FormState(
                    emailCtrl: _emailCtrl,
                    loading: _loading,
                    error: _error,
                    onSend: _sendReset,
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Estado: formulario ───────────────────────────────────────────────────────

class _FormState extends StatelessWidget {
  const _FormState({
    required this.emailCtrl,
    required this.loading,
    required this.error,
    required this.onSend,
  });

  final TextEditingController emailCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthLogo(),
        const SizedBox(height: 8),
        const Text(
          'OmniGym',
          style: TextStyle(
            color: OmniGymColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Recuperar contraseña',
          style: TextStyle(
            color: OmniGymColors.textSecondary,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        AuthDarkField(
          controller: emailCtrl,
          label: 'Correo electrónico',
          prefixIcon: Icons.person_outline,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => onSend(),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          AuthErrorBanner(message: error!),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading ? null : onSend,
          child: loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Enviar correo de recuperación'),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.go('/login'),
          style: TextButton.styleFrom(
            foregroundColor: OmniGymColors.textSecondary,
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text('Regresar a inicio de sesión'),
        ),
      ],
    );
  }
}

// ─── Estado: enviado ──────────────────────────────────────────────────────────

class _SentState extends StatelessWidget {
  const _SentState({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('sent'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: OmniGymColors.success.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(
                color: OmniGymColors.success.withAlpha(80),
              ),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: OmniGymColors.success,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Correo enviado',
          style: TextStyle(
            color: OmniGymColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Enviamos un enlace de recuperación a\n$email\n\nRevisa tu bandeja de entrada.',
          style: const TextStyle(
            color: OmniGymColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Regresar a inicio de sesión'),
        ),
      ],
    );
  }
}

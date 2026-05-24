import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/providers/providers.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mapError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapError(String code) => switch (code) {
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'wrong-password' => 'Contraseña incorrecta.',
        'invalid-credential' => 'Correo o contraseña incorrectos.',
        'invalid-email' => 'Correo electrónico inválido.',
        'user-disabled' => 'Esta cuenta ha sido deshabilitada.',
        _ => 'Error al iniciar sesión. Intenta de nuevo.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: AuthCard(
          child: Column(
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
                'Portal de administración',
                style: TextStyle(
                  color: OmniGymColors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              AuthDarkField(
                controller: _emailCtrl,
                label: 'Correo electrónico',
                prefixIcon: Icons.person_outline,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 14),

              AuthDarkField(
                controller: _passCtrl,
                label: 'Contraseña',
                prefixIcon: Icons.lock_outline,
                obscureText: _obscurePass,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility,
                    color: OmniGymColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
                onSubmitted: (_) => _signIn(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                AuthErrorBanner(message: _error!),
              ],

              const SizedBox(height: 20),

              FilledButton(
                onPressed: _loading ? null : _signIn,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Iniciar sesión'),
              ),

              const SizedBox(height: 16),
              const AuthDivider(),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => context.go('/forgot-password'),
                style: TextButton.styleFrom(
                  foregroundColor: OmniGymColors.textSecondary,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => context.go('/register'),
                style: TextButton.styleFrom(
                  foregroundColor: OmniGymColors.primary,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Registrar nuevo gimnasio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

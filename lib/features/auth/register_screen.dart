import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/models/app_user.dart';
import '../../core/models/tenant.dart';
import '../../core/providers/providers.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gymNameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _gymNameCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(firebaseAuthProvider);
      final db = ref.read(firestoreProvider);

      // 1. Crear cuenta en Firebase Auth
      final credential = await auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      final uid = credential.user!.uid;
      await credential.user!.updateDisplayName(_nameCtrl.text.trim());

      // 2. Crear el Tenant
      final gymName = _gymNameCtrl.text.trim();
      final tenantRef = db.collection('tenants').doc();
      final tenantId = tenantRef.id;
      await tenantRef.set({
        'name': gymName,
        'slug': _slugify(gymName),
        'subscription_status': SubscriptionStatus.active.name,
        'billing_cycle_end': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30)),
        ),
        'settings': const TenantSettings().toJson(),
        'created_at': FieldValue.serverTimestamp(),
      });

      // 3. Crear /users/{uid} — dispara onUserWritten que asigna custom claims
      await db.collection('users').doc(uid).set({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'role': UserRole.owner.name,
        'status': UserStatus.active.name,
        'tenant_id': tenantId,
        'branch_id': null,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 4. Esperar claims — onUserWritten tarda ~1-3s en producción
      await _waitForClaims(credential.user!);

      // El router reacciona al cambio de authState y redirige a /dashboard/owner
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mapError(e.code));
    } catch (e) {
      setState(() => _error = 'Error inesperado. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _waitForClaims(User user) async {
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 800));
      final result = await user.getIdTokenResult(true);
      if (result.claims?['role'] != null) return;
    }
  }

  String _slugify(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll(RegExp(r'ñ'), 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  String _mapError(String code) => switch (code) {
        'email-already-in-use' => 'Ya existe una cuenta con ese correo.',
        'invalid-email' => 'Correo electrónico inválido.',
        'weak-password' => 'La contraseña es muy débil (mínimo 6 caracteres).',
        _ => 'Error al crear la cuenta. Intenta de nuevo.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: AuthCard(
          child: Form(
            key: _formKey,
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
                  'Registra tu gimnasio',
                  style: TextStyle(
                    color: OmniGymColors.textSecondary,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                AuthDarkField(
                  controller: _gymNameCtrl,
                  label: 'Nombre del gimnasio',
                  prefixIcon: Icons.fitness_center,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),

                AuthDarkField(
                  controller: _nameCtrl,
                  label: 'Tu nombre completo',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),

                AuthDarkField(
                  controller: _emailCtrl,
                  label: 'Correo electrónico',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    if (!v.contains('@')) return 'Correo inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                AuthDarkField(
                  controller: _passCtrl,
                  label: 'Contraseña',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePass,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: OmniGymColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Requerido';
                    if (v.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                AuthDarkField(
                  controller: _confirmCtrl,
                  label: 'Confirmar contraseña',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscureConfirm,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: OmniGymColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) => v != _passCtrl.text
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  AuthErrorBanner(message: _error!),
                ],

                const SizedBox(height: 24),

                if (_loading)
                  const _LoadingState()
                else
                  FilledButton(
                    onPressed: _register,
                    child: const Text('Crear cuenta'),
                  ),

                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/login'),
                  style: TextButton.styleFrom(
                    foregroundColor: OmniGymColors.textSecondary,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('¿Ya tienes cuenta? Inicia sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(
          height: 36,
          width: 36,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: OmniGymColors.primary,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Configurando tu gimnasio…',
          style: TextStyle(
            color: OmniGymColors.textSecondary,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/services/login_identity.dart';
import '../../core/services/staff_account_service.dart';
import 'auth_widgets.dart';

class StaffInvitationScreen extends ConsumerStatefulWidget {
  const StaffInvitationScreen({
    super.key,
    required this.id,
    required this.token,
    required this.code,
  });
  final String id;
  final String token;
  final String code;

  @override
  ConsumerState<StaffInvitationScreen> createState() =>
      _StaffInvitationScreenState();
}

class _StaffInvitationScreenState extends ConsumerState<StaffInvitationScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final Future<StaffInvitation> _invitation;
  bool _busy = false;
  bool _rejected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invitation = ref
        .read(staffAccountServiceProvider)
        .preview(widget.id, widget.token);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _respond(StaffInvitation invitation, bool accept) async {
    if (accept && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(staffAccountServiceProvider);
      if (accept) {
        final auth = ref.read(firebaseAuthProvider);
        final email = LoginIdentity.emailFor(invitation.username);
        try {
          final resetEmail = await auth.verifyPasswordResetCode(widget.code);
          if (resetEmail.toLowerCase() != email) {
            throw const StaffAccountException(
              'El enlace de contraseña no corresponde a esta invitación. Solicita un reenvío.',
            );
          }
          await auth.confirmPasswordReset(
            code: widget.code,
            newPassword: _password.text,
          );
        } on FirebaseAuthException catch (e) {
          // Resume an activation interrupted after password setup: the identity
          // must still authenticate and the backend must validate the invitation.
          if (!const {
            'invalid-action-code',
            'expired-action-code',
          }.contains(e.code)) {
            rethrow;
          }
        }
        final credentials = await auth.signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
        final idToken = await credentials.user!.getIdToken(true);
        if (idToken == null) {
          throw const StaffAccountException(
            'No se pudo verificar tu acceso. Intenta de nuevo.',
          );
        }
        await service.accept(widget.id, widget.token, idToken);
        if (mounted) context.go('/login');
      } else {
        await service.reject(widget.id, widget.token);
        if (mounted) setState(() => _rejected = true);
      }
    } on StaffAccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.code) {
            'weak-password' => 'Elige una contraseña más segura.',
            'invalid-credential' || 'wrong-password' => 'No se pudo configurar el acceso. Si ya estableciste una contraseña, usa esa misma; de lo contrario solicita un reenvío al gimnasio.',
            'too-many-requests' => 'Demasiados intentos. Espera unos minutos.',
            _ => 'No se pudo configurar el acceso. Intenta de nuevo o solicita un reenvío al gimnasio.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo completar la operación. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthPage(
    builder: (context) => FutureBuilder<StaffInvitation>(
      future: _invitation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Invitación no disponible'),
              const SizedBox(height: 16),
              Text(
                snapshot.error is StaffAccountException
                    ? (snapshot.error as StaffAccountException).message
                    : 'No se pudo consultar la invitación. Intenta abrir el enlace nuevamente.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Ir al inicio'),
              ),
            ],
          );
        }
        if (_rejected) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Invitación rechazada. No se habilitó acceso al gimnasio.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Ir al inicio'),
              ),
            ],
          );
        }
        final invitation = snapshot.data!;
        return Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthLogo(),
              const SizedBox(height: 20),
              Text(
                'Invitación a ${invitation.gymName}',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Hola, ${invitation.name}.\nSucursal: ${invitation.branchName}\nRol: ${invitation.role == 'staff' ? 'Staff (encargado)' : 'Recepcionista'}',
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Usuario laboral: ${invitation.username}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Acepta la invitación y establece tu contraseña para activar esta cuenta laboral.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _password,
                obscureText: true,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
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
                onPressed: _busy ? null : () => _respond(invitation, true),
                child: Text(_busy ? 'Procesando…' : 'Aceptar y activar cuenta'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _respond(invitation, false),
                child: const Text('Rechazar invitación'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

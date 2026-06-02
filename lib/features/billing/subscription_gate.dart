import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/models/billing_access.dart';
import '../../core/models/tenant.dart';

/// Copy amigable por estado de cobro, reutilizado por el banner y el diálogo.
({String title, String message, String cta, IconData icon, Color color})
    billingCopy(Tenant tenant) {
  switch (tenant.billingState) {
    case BillingState.none:
      return (
        title: 'Activa tu prueba gratis',
        message:
            'Tienes 14 días gratis para usar OmniGym. Agrega tu tarjeta para '
            'empezar; no se te cobrará hasta que termine la prueba y puedes '
            'cancelar cuando quieras.',
        cta: 'Empezar prueba gratis',
        icon: Icons.rocket_launch_outlined,
        color: OmniGymColors.primary,
      );
    case BillingState.trialing:
      final d = tenant.daysUntilCycleEnd;
      return (
        title: 'Estás en tu prueba gratis',
        message: d <= 1
            ? 'Tu prueba termina hoy. Tu plan se activará automáticamente.'
            : 'Quedan $d días de prueba. Después se activará tu plan '
                'automáticamente con la tarjeta que registraste.',
        cta: 'Ver mi suscripción',
        icon: Icons.timer_outlined,
        color: OmniGymColors.primary,
      );
    case BillingState.pastDue:
      return (
        title: 'Pago pendiente',
        message:
            'No pudimos cobrar tu suscripción. Actualiza tu método de pago '
            'para reactivar el acceso del gimnasio.',
        cta: 'Actualizar pago',
        icon: Icons.warning_amber_rounded,
        color: OmniGymColors.errorRed,
      );
    case BillingState.inactive:
      return (
        title: 'Suscripción inactiva',
        message:
            'Tu suscripción terminó. Elige un plan para seguir operando tu '
            'gimnasio con OmniGym.',
        cta: 'Elegir plan',
        icon: Icons.lock_outline,
        color: OmniGymColors.errorRed,
      );
    case BillingState.active:
      return (
        title: 'Suscripción activa',
        message: 'Tu gimnasio está al corriente.',
        cta: 'Ver mi suscripción',
        icon: Icons.check_circle_outline,
        color: OmniGymColors.success,
      );
  }
}

/// Diálogo de bloqueo suave: aparece al intentar una acción operativa sin
/// suscripción/prueba activa. Invita a "Mi suscripción" sin ser agresivo.
Future<void> showSubscriptionGateDialog(
    BuildContext context, Tenant tenant) async {
  final c = billingCopy(tenant);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: OmniGymColors.card,
      icon: Icon(c.icon, color: c.color, size: 32),
      title: Text(c.title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: OmniGymColors.textPrimary)),
      content: Text(c.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: OmniGymColors.textSecondary, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ctx.go('/subscription');
          },
          child: Text(c.cta),
        ),
      ],
    ),
  );
}

/// Banner persistente y amigable. Se oculta cuando la suscripción está activa.
class SubscriptionBanner extends StatelessWidget {
  const SubscriptionBanner({super.key, required this.tenant});
  final Tenant tenant;

  @override
  Widget build(BuildContext context) {
    if (tenant.billingState == BillingState.active) {
      return const SizedBox.shrink();
    }
    final c = billingCopy(tenant);
    return Material(
      color: c.color.withAlpha(28),
      child: InkWell(
        onTap: () => context.go('/subscription'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(c.icon, color: c.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.title,
                  style: TextStyle(
                      color: c.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.color,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => context.go('/subscription'),
                child: Text(c.cta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

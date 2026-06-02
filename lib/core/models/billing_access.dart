import 'tenant.dart';

/// Estado de cobro SaaS derivado, para decidir acceso y mensajes en la app.
///
/// Es distinto de [Tenant.subscriptionStatus] (kill switch operativo): aquí se
/// modela el ciclo real del cobro con Stripe, incluyendo el periodo de prueba.
enum BillingState {
  /// Nunca inició prueba/plan (gym recién creado). Debe iniciar su prueba.
  none,

  /// En periodo de prueba gratis (tarjeta guardada, aún sin cobro).
  trialing,

  /// Suscripción pagada y vigente.
  active,

  /// Pago pendiente/rechazado.
  pastDue,

  /// Cancelada o terminada.
  inactive,
}

extension TenantBilling on Tenant {
  BillingState get billingState {
    if (pastDue) return BillingState.pastDue;
    final s = stripeSubscriptionStatus;
    if (s == 'trialing') return BillingState.trialing;
    if (subscriptionStatus != SubscriptionStatus.active) {
      return BillingState.inactive;
    }
    // Operativamente activo: si nunca pasó por checkout, sigue en onboarding.
    if (packagePriceId == null) return BillingState.none;
    return BillingState.active;
  }

  /// El gimnasio puede realizar acciones operativas (check-in, alta de socios).
  bool get canOperate {
    final st = billingState;
    return st == BillingState.trialing || st == BillingState.active;
  }

  /// Días restantes hasta [billingCycleEnd] (0 si ya pasó). Útil para el banner
  /// de prueba ("quedan X días").
  int get daysUntilCycleEnd {
    final diff = billingCycleEnd.difference(DateTime.now()).inHours;
    if (diff <= 0) return 0;
    return (diff / 24).ceil();
  }
}

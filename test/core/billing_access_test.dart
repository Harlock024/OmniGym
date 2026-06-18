import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/billing_access.dart';
import 'package:omnigym/core/models/tenant.dart';

void main() {
  group('TenantBilling', () {
    final base = Tenant(
      id: 't1',
      slug: 'gym-test',
      name: 'Gym Test',
      subscriptionStatus: SubscriptionStatus.active,
      billingCycleEnd: DateTime.now().add(const Duration(days: 30)),
      settings: const TenantSettings(),
      pastDue: false,
    );

    test('billingState none cuando no tiene packagePriceId', () {
      final tenant = base.copyWith(packagePriceId: null);
      expect(tenant.billingState, BillingState.none);
    });

    test('billingState trialing cuando stripeSubscriptionStatus es trialing', () {
      final tenant = base.copyWith(
        packagePriceId: 'price_123',
        stripeSubscriptionStatus: 'trialing',
      );
      expect(tenant.billingState, BillingState.trialing);
    });

    test('billingState active cuando tiene packagePriceId y status activo', () {
      final tenant = base.copyWith(
        packagePriceId: 'price_123',
        stripeSubscriptionStatus: 'active',
      );
      expect(tenant.billingState, BillingState.active);
    });

    test('billingState pastDue cuando pastDue es true', () {
      final tenant = base.copyWith(
        packagePriceId: 'price_123',
        pastDue: true,
      );
      expect(tenant.billingState, BillingState.pastDue);
    });

    test('billingState inactive cuando subscriptionStatus no es active', () {
      final tenant = base.copyWith(
        subscriptionStatus: SubscriptionStatus.cancelled,
        packagePriceId: 'price_123',
      );
      expect(tenant.billingState, BillingState.inactive);
    });

    test('canOperate es true en trialing', () {
      final tenant = base.copyWith(
        packagePriceId: 'price_123',
        stripeSubscriptionStatus: 'trialing',
      );
      expect(tenant.canOperate, isTrue);
    });

    test('canOperate es true en active', () {
      final tenant = base.copyWith(
        packagePriceId: 'price_123',
        stripeSubscriptionStatus: 'active',
      );
      expect(tenant.canOperate, isTrue);
    });

    test('canOperate es false en pastDue', () {
      final tenant = base.copyWith(
        packagePriceId: 'price_123',
        pastDue: true,
      );
      expect(tenant.canOperate, isFalse);
    });

    test('canOperate es false en none', () {
      final tenant = base.copyWith(packagePriceId: null);
      expect(tenant.canOperate, isFalse);
    });

    test('daysUntilCycleEnd devuelve dias correctos', () {
      final future = DateTime.now().add(const Duration(hours: 72));
      final tenant = base.copyWith(
        billingCycleEnd: future,
        packagePriceId: 'price_123',
      );
      expect(tenant.daysUntilCycleEnd, 3);
    });

    test('daysUntilCycleEnd devuelve 0 si ya paso', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final tenant = base.copyWith(billingCycleEnd: past);
      expect(tenant.daysUntilCycleEnd, 0);
    });
  });
}

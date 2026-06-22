import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/billing_access.dart';
import '../../core/models/tenant.dart';
import '../../core/providers/providers.dart';
import '../../core/services/worker_service.dart';
import '../superadmin/subscription_packages_screen.dart';
import 'subscription_gate.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() getUrl) async {
    setState(() => _busy = true);
    try {
      final url = await getUrl();
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _subscribe(String tenantId, String priceId) => _run(() {
        final ret = kIsWeb ? Uri.base.toString() : null;
        return WorkerService.createCheckout(
            tenantId: tenantId, priceId: priceId, successUrl: ret, cancelUrl: ret);
      });

  Future<void> _manage(String tenantId) => _run(() {
        final ret = kIsWeb ? Uri.base.toString() : null;
        return WorkerService.billingPortal(tenantId: tenantId, returnUrl: ret);
      });

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(activeTenantProvider);
    final packagesAsync = ref.watch(subscriptionPackagesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: context.isMobile ? const DrawerMenuButton() : null,
        automaticallyImplyLeading: false,
        title: const Text('Mi suscripción'),
        actions: [
          // Cuando es el muro de bloqueo (sin barra lateral), ofrecer salir.
          if (!(tenantAsync.valueOrNull?.canOperate ?? true))
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              tooltip: 'Cerrar sesión',
              onPressed: () => ref.read(firebaseAuthProvider).signOut(),
            ),
        ],
      ),
      body: tenantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tenant) {
          if (tenant == null) {
            return const Center(child: Text('No se encontró tu gimnasio.'));
          }
          // Solo se ofrecen planes cuando NO hay suscripción/prueba en curso:
          // gym nuevo (none) o suscripción terminada (inactive). En prueba o
          // activo no se muestran (ya tiene plan); en pago vencido se usa el
          // botón "Gestionar" (portal) para actualizar la tarjeta.
          final st = tenant.billingState;
          final showPlans =
              st == BillingState.none || st == BillingState.inactive;
          final packages = (packagesAsync.valueOrNull ?? [])
              .where((p) => p.active && p.stripePriceId.isNotEmpty)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _StatusCard(
                tenant: tenant,
                busy: _busy,
                onManage: tenant.stripeCustomerId != null
                    ? () => _manage(tenant.id)
                    : null,
              ),
              if (showPlans) ...[
                const SizedBox(height: 24),
                Text('Planes disponibles',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                if (packagesAsync.isLoading)
                  const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
                else if (packages.isEmpty)
                  Text('No hay planes disponibles por el momento.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                else
                  ...packages.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PackageOption(
                          pkg: p,
                          busy: _busy,
                          onSubscribe: () =>
                              _subscribe(tenant.id, p.stripePriceId),
                        ),
                      )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.tenant, required this.busy, this.onManage});
  final Tenant tenant;
  final bool busy;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final c = billingCopy(tenant);
    final st = tenant.billingState;

    final d = tenant.billingCycleEnd;
    final fecha =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    // Subtítulo: para activo mostramos el próximo cobro; para el resto, el
    // mensaje del estado (prueba, pago pendiente, etc.).
    final subtitle = st == BillingState.active
        ? 'Próximo cobro: $fecha'
        : c.message;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(c.icon, color: c.color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    st == BillingState.active ? 'Suscripción activa' : c.title,
                    style: TextStyle(
                        color: c.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          if (onManage != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : onManage,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Gestionar suscripción'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PackageOption extends StatelessWidget {
  const _PackageOption(
      {required this.pkg, required this.busy, required this.onSubscribe});
  final SubscriptionPackage pkg;
  final bool busy;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final limits = <String>[
      if (pkg.branches != null) '${pkg.branches} sucursales',
      if (pkg.checkins != null) '${pkg.checkins} check-ins',
      if (pkg.staff != null) '${pkg.staff} staff',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pkg.name,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('\$${pkg.price.toStringAsFixed(2)} ${pkg.currency.toUpperCase()} / mes',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600)),
                if (limits.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(limits,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : onSubscribe,
            child: const Text('Suscribirme'),
          ),
        ],
      ),
    );
  }
}

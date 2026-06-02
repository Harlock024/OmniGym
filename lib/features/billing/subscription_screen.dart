import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/tenant.dart';
import '../../core/providers/providers.dart';
import '../../core/services/worker_service.dart';
import '../superadmin/subscription_packages_screen.dart';

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
      backgroundColor: OmniGymColors.background,
      appBar: AppBar(
        leading: context.isMobile ? const DrawerMenuButton() : null,
        automaticallyImplyLeading: false,
        title: const Text('Mi suscripción'),
      ),
      body: tenantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tenant) {
          if (tenant == null) {
            return const Center(child: Text('No se encontró tu gimnasio.'));
          }
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
              const SizedBox(height: 24),
              const Text('Planes disponibles',
                  style: TextStyle(
                      color: OmniGymColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (packagesAsync.isLoading)
                const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
              else if (packages.isEmpty)
                const Text('No hay planes disponibles por el momento.',
                    style: TextStyle(color: OmniGymColors.textSecondary))
              else
                ...packages.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PackageOption(
                        pkg: p,
                        busy: _busy,
                        onSubscribe: () => _subscribe(tenant.id, p.stripePriceId),
                      ),
                    )),
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
    final active = tenant.subscriptionStatus == SubscriptionStatus.active;
    final pastDue = tenant.pastDue;

    final (Color color, String label, IconData icon) = pastDue
        ? (OmniGymColors.errorRed, 'Pago vencido', Icons.warning_amber_rounded)
        : active
            ? (OmniGymColors.primary, 'Suscripción activa', Icons.check_circle)
            : (OmniGymColors.textSecondary, 'Sin suscripción activa', Icons.info_outline);

    final d = tenant.billingCycleEnd;
    final fecha =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pastDue
                ? 'Tu último pago no se completó. Renueva para no perder el acceso.'
                : active
                    ? 'Próximo cobro: $fecha'
                    : 'Elige un plan abajo para activar tu suscripción.',
            style: const TextStyle(
                color: OmniGymColors.textSecondary, fontSize: 13),
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
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pkg.name,
                    style: const TextStyle(
                        color: OmniGymColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('\$${pkg.price.toStringAsFixed(2)} ${pkg.currency.toUpperCase()} / mes',
                    style: const TextStyle(
                        color: OmniGymColors.primary,
                        fontWeight: FontWeight.w600)),
                if (limits.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(limits,
                      style: const TextStyle(
                          color: OmniGymColors.textSecondary, fontSize: 12)),
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

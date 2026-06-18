import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/tenant.dart';
import 'superadmin_providers.dart';

class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(filteredTenantsProvider);
    final search = ref.watch(tenantSearchProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(searchValue: search, ref: ref),
          const _ColumnHeaders(),
          Expanded(
            child: tenantsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: OmniGymColors.textSecondary)),
              ),
              data: (tenants) => tenants.isEmpty
                  ? _EmptyState(hasSearch: search.isNotEmpty)
                  : _TenantTable(tenants: tenants),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.searchValue, required this.ref});
  final String searchValue;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: OmniGymColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (context.isMobile) const DrawerMenuButton(),
              const Text(
                'Empresas',
                style: TextStyle(
                  color: OmniGymColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Consumer(builder: (_, ref, _) {
                final count =
                    ref.watch(allTenantsProvider).valueOrNull?.length ?? 0;
                return Text(
                  '$count registradas',
                  style: const TextStyle(
                    color: OmniGymColors.textSecondary,
                    fontSize: 13,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) =>
                  ref.read(tenantSearchProvider.notifier).state = v,
              style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, RFC o contacto...',
                hintStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: OmniGymColors.textSecondary, size: 18),
                filled: true,
                fillColor: OmniGymColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OmniGymColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OmniGymColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: OmniGymColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tabla de tenants ─────────────────────────────────────────────────────────

class _TenantTable extends StatelessWidget {
  const _TenantTable({required this.tenants});
  final List<Tenant> tenants;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(0),
      itemCount: tenants.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: OmniGymColors.border),
      itemBuilder: (context, i) => _TenantRow(tenant: tenants[i]),
    );
  }
}

class _TenantRow extends StatelessWidget {
  const _TenantRow({required this.tenant});
  final Tenant tenant;

  @override
  Widget build(BuildContext context) {
    final settings = tenant.settings;

    return InkWell(
      onTap: () => context.go('/superadmin/tenant/${tenant.id}'),
      hoverColor: OmniGymColors.surface.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            // Avatar / logo
            _TenantAvatar(
              logoUrl: settings.logoUrl,
              name: tenant.name,
              color: settings.primaryColor,
            ),
            const SizedBox(width: 14),
            // Nombre
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenant.name,
                    style: const TextStyle(
                      color: OmniGymColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    tenant.slug,
                    style: const TextStyle(
                      color: OmniGymColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // RFC
            Expanded(
              flex: 2,
              child: Text(
                settings.rfc ?? '—',
                style: const TextStyle(
                  color: OmniGymColors.textSecondary,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // Contacto
            Expanded(
              flex: 2,
              child: Text(
                settings.contactName ?? '—',
                style: const TextStyle(
                  color: OmniGymColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            // Estado suscripción + próximo cobro
            _StatusBadge(tenant: tenant),
            const SizedBox(width: 16),
            // Flecha
            const Icon(Icons.chevron_right,
                color: OmniGymColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Encabezados de columna ───────────────────────────────────────────────────

class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: OmniGymColors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: OmniGymColors.surface,
        border: Border(
            bottom: BorderSide(color: OmniGymColors.border, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 46),
          const Expanded(flex: 3, child: Text('NOMBRE', style: style)),
          const Expanded(flex: 2, child: Text('RFC', style: style)),
          const Expanded(flex: 2, child: Text('CONTACTO', style: style)),
          const Text('ESTADO', style: style),
          const SizedBox(width: 50),
        ],
      ),
    );
  }
}

// ─── Avatar del tenant ────────────────────────────────────────────────────────

class TenantAvatar extends StatelessWidget {
  const TenantAvatar({
    super.key,
    this.logoUrl,
    required this.name,
    required this.color,
    this.radius = 18,
  });

  final String? logoUrl;
  final String name;
  final String color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brandColor = _parseColor(color);
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(logoUrl!),
        backgroundColor: brandColor,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: brandColor,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return OmniGymColors.primary;
    }
  }
}

// Alias privado para uso interno en este archivo
class _TenantAvatar extends TenantAvatar {
  const _TenantAvatar({
    super.logoUrl,
    required super.name,
    required super.color,
  }) : super(radius: 18);
}

// ─── Badge de estado ──────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.tenant});
  final Tenant tenant;

  @override
  Widget build(BuildContext context) {
    final pastDue =
        tenant.pastDue && tenant.subscriptionStatus == SubscriptionStatus.active;

    final (label, color) = pastDue
        ? ('Pago vencido', OmniGymColors.errorRed)
        : switch (tenant.subscriptionStatus) {
            SubscriptionStatus.active => ('Activo', OmniGymColors.success),
            SubscriptionStatus.suspended => ('Suspendido', Colors.orange),
            SubscriptionStatus.cancelled =>
              ('Cancelado', OmniGymColors.errorRed),
          };

    final d = tenant.billingCycleEnd;
    final fecha =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Próx. cobro $fecha',
          style: const TextStyle(
              color: OmniGymColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch});
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.business_outlined,
            size: 48,
            color: OmniGymColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch
                ? 'Sin resultados para esa búsqueda'
                : 'No hay empresas registradas',
            style: const TextStyle(
                color: OmniGymColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

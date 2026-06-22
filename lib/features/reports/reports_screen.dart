import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/payment.dart';
import '../../core/providers/providers.dart';

// ─── Período ──────────────────────────────────────────────────────────────────

enum _Period {
  thisMonth('Este mes'),
  lastMonth('Mes pasado'),
  last3Months('Últimos 3 meses'),
  last12Months('Últimos 12 meses');

  const _Period(this.label);
  final String label;

  ({DateTime start, DateTime end}) get range {
    final now = DateTime.now();
    return switch (this) {
      _Period.thisMonth => (
          start: DateTime(now.year, now.month, 1),
          end: now,
        ),
      _Period.lastMonth => (
          start: DateTime(now.year, now.month - 1, 1),
          end: DateTime(now.year, now.month, 1)
              .subtract(const Duration(seconds: 1)),
        ),
      _Period.last3Months => (
          start: DateTime(now.year, now.month - 2, 1),
          end: now,
        ),
      _Period.last12Months => (
          start: DateTime(now.year - 1, now.month, 1),
          end: now,
        ),
    };
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final _periodProvider = StateProvider<_Period>((_) => _Period.thisMonth);

final _reportPaymentsProvider = FutureProvider.autoDispose
    .family<List<Payment>, ({String tenantId, _Period period})>(
  (ref, args) async {
    final r = args.period.range;
    return ref.read(paymentRepositoryProvider).fetchByPeriod(
          args.tenantId,
          r.start,
          r.end,
        );
  },
);

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantAsync = ref.watch(activeTenantIdFutureProvider);
    final period = ref.watch(_periodProvider);
    final tenantId = tenantAsync.valueOrNull ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, ref, period),
          Expanded(
            child: tenantId.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _ReportBody(tenantId: tenantId, period: period),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, _Period current) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (context.isMobile) const DrawerMenuButton(),
              Text(
                'Reportes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _Period.values.map((p) {
                final selected = p == current;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: selected,
                    onSelected: (_) =>
                        ref.read(_periodProvider.notifier).state = p,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.tenantId, required this.period});
  final String tenantId;
  final _Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(
      _reportPaymentsProvider((tenantId: tenantId, period: period)),
    );
    final membersAsync = ref.watch(membersProvider(tenantId));

    return paymentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
      data: (payments) {
        final r = period.range;
        final members = membersAsync.valueOrNull ?? [];
        final newMembers = members
            .where((m) =>
                m.createdAt != null &&
                m.createdAt!.isAfter(r.start) &&
                m.createdAt!.isBefore(r.end))
            .length;
        final activeMembers =
            members.where((m) => m.accessStatus.name == 'active').length;

        final totalRevenue =
            payments.fold<double>(0, (sum, p) => sum + p.amount);
        final weeklyData = _groupByWeek(payments, r.start, r.end);
        final planBreakdown = _groupByPlan(payments);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── KPI cards ─────────────────────────────────────────────
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _KpiCard(
                  label: 'Ingresos',
                  value:
                      '\$${_fmt(totalRevenue)}',
                  icon: Icons.payments_rounded,
                  color: OmniGymColors.success,
                ),
                _KpiCard(
                  label: 'Pagos',
                  value: '${payments.length}',
                  icon: Icons.receipt_long_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                _KpiCard(
                  label: 'Socios nuevos',
                  value: '$newMembers',
                  icon: Icons.person_add_rounded,
                  color: const Color(0xFF0891B2),
                ),
                _KpiCard(
                  label: 'Socios activos',
                  value: '$activeMembers',
                  icon: Icons.people_rounded,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Gráfica de ingresos ────────────────────────────────────
            if (weeklyData.isNotEmpty) ...[
              _RevenueChart(data: weeklyData),
              const SizedBox(height: 24),
            ],

            // ── Desglose por plan ──────────────────────────────────────
            if (planBreakdown.isNotEmpty)
              _PlanBreakdownCard(breakdown: planBreakdown, total: totalRevenue),
          ],
        );
      },
    );
  }

  static String _fmt(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  static List<({String label, double amount, int count})> _groupByWeek(
    List<Payment> payments,
    DateTime start,
    DateTime end,
  ) {
    final diff = end.difference(start).inDays;
    // Agrupar por semana si el período es > 2 semanas, sino por día
    final byDay = diff > 14;
    final groups = <String, ({double amount, int count})>{};

    for (final p in payments) {
      final dt = p.createdAt;
      final String key;
      if (byDay) {
        // Semana del año
        final weekStart = dt.subtract(Duration(days: dt.weekday - 1));
        key =
            '${weekStart.day.toString().padLeft(2, '0')}/${weekStart.month.toString().padLeft(2, '0')}';
      } else {
        key =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      }
      final prev = groups[key] ?? (amount: 0.0, count: 0);
      groups[key] = (amount: prev.amount + p.amount, count: prev.count + 1);
    }

    return groups.entries
        .map((e) => (label: e.key, amount: e.value.amount, count: e.value.count))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  static List<({String plan, int count, double total})> _groupByPlan(
      List<Payment> payments) {
    final groups = <String, ({int count, double total})>{};
    for (final p in payments) {
      final name = p.planName ?? 'Sin plan';
      final prev = groups[name] ?? (count: 0, total: 0.0);
      groups[name] = (count: prev.count + 1, total: prev.total + p.amount);
    }
    return groups.entries
        .map((e) => (plan: e.key, count: e.value.count, total: e.value.total))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }
}

// ─── KPI card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Revenue chart ────────────────────────────────────────────────────────────

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.data});
  final List<({String label, double amount, int count})> data;

  @override
  Widget build(BuildContext context) {
    final maxY =
        data.map((e) => e.amount).fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ingresos por período',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY == 0 ? 100 : maxY * 1.25,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= data.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            data[i].label,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: data.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.amount,
                        color: Theme.of(context).colorScheme.primary,
                        width: data.length > 8 ? 12 : 20,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxY == 0 ? 100 : maxY * 1.25,
                          color: Theme.of(context).colorScheme.primary.withAlpha(15),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Theme.of(context).colorScheme.surface,
                    getTooltipItem: (group, _, rod, _) {
                      final d = data[group.x];
                      return BarTooltipItem(
                        '\$${rod.toY % 1 == 0 ? rod.toY.toInt() : rod.toY.toStringAsFixed(0)}\n',
                        TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: '${d.count} pago${d.count != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plan breakdown ───────────────────────────────────────────────────────────

class _PlanBreakdownCard extends StatelessWidget {
  const _PlanBreakdownCard(
      {required this.breakdown, required this.total});
  final List<({String plan, int count, double total})> breakdown;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              'Desglose por plan',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
                bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text('Plan',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 70,
                  child: Text('Pagos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 90,
                  child: Text('Ingresos',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 60,
                  child: Text('%',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          ...breakdown.map((row) {
            final pct = total > 0 ? (row.total / total * 100) : 0.0;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(row.plan,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text('${row.count}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13)),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      '\$${row.total % 1 == 0 ? row.total.toInt() : row.total.toStringAsFixed(2)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          color: OmniGymColors.success,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${pct.toStringAsFixed(1)}%',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

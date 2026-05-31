import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/models/branch.dart';
import '../../core/providers/providers.dart';

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  String? _selectedBranchId;

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(activeTenantProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      appBar: AppBar(
        backgroundColor: OmniGymColors.surface,
        title: tenantAsync.whenOrNull(data: (t) => Text(t?.name ?? 'OmniGym')) ??
            const Text('OmniGym'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Escáner',
            onPressed: () => context.push('/scanner'),
          ),
          IconButton(
            icon: const Icon(Icons.tablet_android_rounded),
            tooltip: 'Modo kiosko',
            onPressed: () => context.push('/kiosk'),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Equipo',
            onPressed: () => context.push('/staff'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Mi perfil',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(firebaseAuthProvider).signOut(),
          ),
        ],
      ),
      body: tenantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tenant) {
          if (tenant == null) {
            return const Center(child: Text('Tenant no encontrado.'));
          }
          return _DashboardBody(
            tenantId: tenant.id,
            selectedBranchId: _selectedBranchId,
            onBranchSelected: (id) => setState(() => _selectedBranchId = id),
          );
        },
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.tenantId,
    required this.selectedBranchId,
    required this.onBranchSelected,
  });

  final String tenantId;
  final String? selectedBranchId;
  final ValueChanged<String> onBranchSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(branchesProvider(tenantId));

    return branchesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (branches) {
        if (branches.isEmpty) {
          return const Center(
            child: Text(
              'Sin sucursales. Crea una en el menú "Sucursales".',
              style: TextStyle(color: OmniGymColors.textSecondary),
            ),
          );
        }
        final activeBranch = branches.firstWhere(
          (b) => b.id == selectedBranchId,
          orElse: () => branches.first,
        );
        if (selectedBranchId == null) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => onBranchSelected(activeBranch.id));
        }
        return _DashboardContent(
          tenantId: tenantId,
          branches: branches,
          activeBranch: activeBranch,
          onBranchSelected: onBranchSelected,
        );
      },
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.tenantId,
    required this.branches,
    required this.activeBranch,
    required this.onBranchSelected,
  });

  final String tenantId;
  final List<Branch> branches;
  final Branch activeBranch;
  final ValueChanged<String> onBranchSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchArgs = (tenantId: tenantId, branchId: activeBranch.id);

    final totalActiveAsync = ref.watch(activeTenantMemberCountProvider(tenantId));
    final expiringAsync = ref.watch(expiringMemberCountProvider(tenantId));
    final newThisMonthAsync = ref.watch(newMembersThisMonthProvider(tenantId));
    final todayCheckInsAsync = ref.watch(todayCheckInCountProvider(branchArgs));
    final activeBranchMembersAsync = ref.watch(activeMemberCountProvider(branchArgs));
    final dailyAsync = ref.watch(dailyCheckInsProvider(branchArgs));
    final recentAsync = ref.watch(recentCheckInsProvider(branchArgs));

    final now = DateTime.now();
    final weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final dateStr =
        '${weekdays[now.weekday - 1]}, ${now.day} de ${_monthName(now.month)} ${now.year}';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Encabezado ───────────────────────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dashboard',
              style: TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: const TextStyle(
                  color: OmniGymColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── KPI strip ────────────────────────────────────────────────────
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _KpiCard(
              label: 'Socios activos',
              icon: Icons.people_rounded,
              valueAsync: totalActiveAsync,
              color: OmniGymColors.primary,
            ),
            _KpiCard(
              label: 'Por vencer (7d)',
              icon: Icons.warning_amber_rounded,
              valueAsync: expiringAsync,
              color: const Color(0xFFF59E0B),
            ),
            _KpiCard(
              label: 'Nuevos este mes',
              icon: Icons.person_add_rounded,
              valueAsync: newThisMonthAsync,
              color: const Color(0xFF10B981),
            ),
            _KpiCard(
              label: 'Sucursales activas',
              icon: Icons.store_rounded,
              value: branches.where((b) => b.isActive).length.toString(),
              color: const Color(0xFF8B5CF6),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Selector de sucursal ─────────────────────────────────────────
        if (branches.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: branches.map((b) {
                final selected = b.id == activeBranch.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(b.name),
                    selected: selected,
                    onSelected: (_) => onBranchSelected(b.id),
                    backgroundColor: OmniGymColors.surface,
                    selectedColor: OmniGymColors.primary,
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : OmniGymColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Gráfica + Aforo ──────────────────────────────────────────────
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 640) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: _LineChartCard(
                      branchName: activeBranch.name,
                      dailyAsync: dailyAsync,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 220,
                    child: _AforoCard(
                      todayAsync: todayCheckInsAsync,
                      activeAsync: activeBranchMembersAsync,
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _LineChartCard(
                    branchName: activeBranch.name, dailyAsync: dailyAsync),
                const SizedBox(height: 16),
                _AforoCard(
                    todayAsync: todayCheckInsAsync,
                    activeAsync: activeBranchMembersAsync),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // ── Actividad reciente ────────────────────────────────────────────
        _RecentActivityCard(recentAsync: recentAsync),
        const SizedBox(height: 16),
      ],
    );
  }

  static String _monthName(int m) => const [
        '',
        'enero',
        'febrero',
        'marzo',
        'abril',
        'mayo',
        'junio',
        'julio',
        'agosto',
        'septiembre',
        'octubre',
        'noviembre',
        'diciembre'
      ][m];
}

// ─── KPI card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.icon,
    required this.color,
    this.valueAsync,
    this.value,
  });

  final String label;
  final IconData icon;
  final Color color;
  final AsyncValue<int>? valueAsync;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value ??
        valueAsync?.when(
          loading: () => '…',
          error: (_, _) => '?',
          data: (v) => v.toString(),
        ) ??
        '…';

    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
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
            displayValue,
            style: const TextStyle(
              color: OmniGymColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: OmniGymColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Line chart ───────────────────────────────────────────────────────────────

class _LineChartCard extends StatelessWidget {
  const _LineChartCard({required this.branchName, required this.dailyAsync});

  final String branchName;
  final AsyncValue<List<({DateTime day, int count})>> dailyAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Check-ins',
                style: TextStyle(
                  color: OmniGymColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Últimos 7 días · $branchName',
                style: const TextStyle(
                  color: OmniGymColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: dailyAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text('Sin datos',
                    style:
                        TextStyle(color: OmniGymColors.textSecondary)),
              ),
              data: (data) {
                final maxY = data
                    .map((e) => e.count)
                    .fold(0, (a, b) => a > b ? a : b)
                    .toDouble();
                final spots = data
                    .asMap()
                    .entries
                    .map((e) => FlSpot(
                        e.key.toDouble(), e.value.count.toDouble()))
                    .toList();
                const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
                return LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY == 0 ? 5 : maxY * 1.3,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: OmniGymColors.border,
                        strokeWidth: 1,
                      ),
                    ),
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
                          reservedSize: 24,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= data.length) {
                              return const SizedBox.shrink();
                            }
                            final weekday =
                                data[idx].day.weekday - 1;
                            return Text(
                              days[weekday % 7],
                              style: const TextStyle(
                                color: OmniGymColors.textSecondary,
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: OmniGymColors.primary,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, _, _, _) =>
                              FlDotCirclePainter(
                            radius: 3,
                            color: OmniGymColors.primary,
                            strokeWidth: 0,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              OmniGymColors.primary.withAlpha(60),
                              OmniGymColors.primary.withAlpha(0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Aforo donut ──────────────────────────────────────────────────────────────

class _AforoCard extends StatelessWidget {
  const _AforoCard({required this.todayAsync, required this.activeAsync});

  final AsyncValue<int> todayAsync;
  final AsyncValue<int> activeAsync;

  @override
  Widget build(BuildContext context) {
    final today = todayAsync.valueOrNull ?? 0;
    final active = activeAsync.valueOrNull ?? 0;
    final loading = todayAsync.isLoading || activeAsync.isLoading;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aforo hoy',
            style: TextStyle(
              color: OmniGymColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            'Check-ins / socios activos',
            style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (loading)
            const SizedBox(
              height: 130,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SizedBox(
              height: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: _buildSections(today, active),
                      centerSpaceRadius: 45,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$today',
                        style: const TextStyle(
                          color: OmniGymColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      Text(
                        'de $active',
                        style: const TextStyle(
                          color: OmniGymColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _Legend(
            color: OmniGymColors.primary,
            label: 'Entraron hoy',
            value: today,
          ),
          const SizedBox(height: 4),
          _Legend(
            color: OmniGymColors.border,
            label: 'No han entrado',
            value: active > today ? active - today : 0,
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections(int today, int active) {
    if (active == 0) {
      return [
        PieChartSectionData(
          value: 1,
          color: OmniGymColors.border,
          radius: 18,
          title: '',
        ),
      ];
    }
    final remaining = (active - today).clamp(0, active).toDouble();
    return [
      PieChartSectionData(
        value: today.toDouble(),
        color: OmniGymColors.primary,
        radius: 18,
        title: '',
      ),
      PieChartSectionData(
        value: remaining,
        color: OmniGymColors.border,
        radius: 18,
        title: '',
      ),
    ];
  }
}

class _Legend extends StatelessWidget {
  const _Legend(
      {required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: OmniGymColors.textSecondary, fontSize: 12)),
        ),
        Text('$value',
            style: const TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Tabla de actividad reciente ──────────────────────────────────────────────

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.recentAsync});
  final AsyncValue<List<Map<String, dynamic>>> recentAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Actividad reciente',
                  style: TextStyle(
                    color: OmniGymColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                recentAsync.whenOrNull(
                      data: (list) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: OmniGymColors.primary.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: OmniGymColors.primary.withAlpha(80)),
                        ),
                        child: Text(
                          '${list.length}',
                          style: const TextStyle(
                              color: OmniGymColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ) ??
                    const SizedBox.shrink(),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: OmniGymColors.border),
                bottom: BorderSide(color: OmniGymColors.border),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(width: 44),
                Expanded(
                  flex: 4,
                  child: Text('Socio',
                      style: TextStyle(
                          color: OmniGymColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Vencimiento',
                      style: TextStyle(
                          color: OmniGymColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 56,
                  child: Text('Hora',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: OmniGymColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          recentAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e',
                  style: const TextStyle(
                      color: OmniGymColors.textSecondary)),
            ),
            data: (checkIns) => checkIns.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Sin accesos registrados hoy.',
                        style: TextStyle(
                            color: OmniGymColors.textSecondary,
                            fontSize: 13),
                      ),
                    ),
                  )
                : Column(
                    children:
                        checkIns.map((ci) => _ActivityRow(data: ci)).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = data['member_name'] as String? ?? '—';
    final ts = data['timestamp'];
    String timeStr = '—';
    if (ts != null) {
      final dt = (ts as dynamic).toDate() as DateTime;
      timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final expDate = data['expiration_date'];
    String expStr = '—';
    bool expired = false;
    if (expDate != null) {
      final exp = (expDate as dynamic).toDate() as DateTime;
      expired = exp.isBefore(DateTime.now());
      expStr =
          '${exp.day.toString().padLeft(2, '0')}/${exp.month.toString().padLeft(2, '0')}/${exp.year}';
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: OmniGymColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: OmniGymColors.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: OmniGymColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              name,
              style: const TextStyle(
                  color: OmniGymColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  expired
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline,
                  size: 14,
                  color: expired
                      ? OmniGymColors.errorRed
                      : OmniGymColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  expStr,
                  style: TextStyle(
                    color: expired
                        ? OmniGymColors.errorRed
                        : OmniGymColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              timeStr,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: OmniGymColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

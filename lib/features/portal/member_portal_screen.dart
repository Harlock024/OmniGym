import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/models/factura.dart';
import '../../core/models/member.dart';
import '../../core/providers/providers.dart';

class MemberPortalScreen extends ConsumerWidget {
  const MemberPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(currentMemberProvider);
    final checkInsAsync = ref.watch(currentMemberCheckInsProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      appBar: AppBar(
        backgroundColor: OmniGymColors.surface,
        title: const Text('Mi membresia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code, color: OmniGymColors.textSecondary),
            tooltip: 'Mi QR',
            onPressed: () => _showQr(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: 'Cerrar sesion',
            onPressed: () => ref.read(firebaseAuthProvider).signOut(),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: OmniGymColors.border),
        ),
      ),
      body: memberAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: OmniGymColors.textSecondary)),
        ),
        data: (member) {
          if (member == null) {
            return const Center(
              child: Text('Socio no encontrado.',
                  style: TextStyle(color: OmniGymColors.textSecondary)),
            );
          }
          final isExpired = member.expirationDate.isBefore(DateTime.now());
          final daysLeft =
              member.expirationDate.difference(DateTime.now()).inDays;
          final isSuspended = member.accessStatus.name != 'active';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MemberCard(
                      name: member.name,
                      email: member.email,
                      isActive: !isExpired && !isSuspended,
                      isSuspended: isSuspended,
                      daysLeft: isExpired ? 0 : daysLeft,
                      expDate: member.expirationDate,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Historial de accesos',
                      style: TextStyle(
                        color: OmniGymColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    checkInsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Text('Error: $e',
                            style: const TextStyle(
                                color: OmniGymColors.textSecondary)),
                      ),
                      data: (checkIns) {
                        if (checkIns.isEmpty) {
                          return const _EmptyHistory();
                        }
                        return _CheckInList(checkIns: checkIns);
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Mis Facturas',
                      style: TextStyle(
                        color: OmniGymColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FacturasSection(member: member),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showQr(BuildContext context, WidgetRef ref) {
    final member = ref.read(currentMemberProvider).valueOrNull;
    if (member == null) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: OmniGymColors.card,
        title: Text('QR - ${member.name}',
            style: const TextStyle(color: OmniGymColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 180,
                height: 180,
                child: Center(
                  child: Text(
                    member.qrToken,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              member.qrToken,
              style: const TextStyle(
                color: OmniGymColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.name,
    required this.email,
    required this.isActive,
    required this.isSuspended,
    required this.daysLeft,
    required this.expDate,
  });

  final String name;
  final String email;
  final bool isActive;
  final bool isSuspended;
  final int daysLeft;
  final DateTime expDate;

  @override
  Widget build(BuildContext context) {
    final color = isSuspended
        ? OmniGymColors.errorRed
        : isActive
            ? OmniGymColors.success
            : OmniGymColors.errorRed;
    final icon = isSuspended
        ? Icons.block
        : isActive
            ? Icons.check_circle
            : Icons.cancel;
    final label = isSuspended
        ? 'Suspendida'
        : isActive
            ? 'Activa'
            : 'Vencida';

    final expStr =
        '${expDate.day.toString().padLeft(2, '0')}/${expDate.month.toString().padLeft(2, '0')}/${expDate.year}';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: color.withAlpha(30),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: color, fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              color: OmniGymColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(
                color: OmniGymColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today,
                  size: 14, color: OmniGymColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                isActive
                    ? 'Vence el $expStr ($daysLeft dias)'
                    : 'Vencio el $expStr',
                style: const TextStyle(
                    color: OmniGymColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckInList extends StatelessWidget {
  const _CheckInList({required this.checkIns});
  final List<Map<String, dynamic>> checkIns;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Column(
        children: checkIns.asMap().entries.map((entry) {
          final ci = entry.value;
          final ts = ci['timestamp'];
          String dateStr = '';
          String timeStr = '';
          if (ts != null) {
            final dt = (ts as dynamic).toDate() as DateTime;
            dateStr =
                '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
            timeStr =
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: entry.key < checkIns.length - 1
                  ? const Border(
                      bottom: BorderSide(color: OmniGymColors.border, width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: OmniGymColors.success.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.login,
                      color: OmniGymColors.success, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Acceso registrado',
                        style: TextStyle(
                            color: OmniGymColors.textPrimary, fontSize: 13),
                      ),
                      Text(
                        dateStr,
                        style: const TextStyle(
                            color: OmniGymColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: OmniGymColors.textSecondary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.history, size: 36, color: OmniGymColors.textSecondary),
          SizedBox(height: 8),
          Text(
            'Sin accesos registrados',
            style: TextStyle(
                color: OmniGymColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _FacturasSection extends ConsumerWidget {
  const _FacturasSection({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = member.tenantId;
    final facturasAsync = ref.watch(tenantFacturasProvider(tenantId));

    return facturasAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Text('Error: \$e'),
      data: (facturas) {
        if (facturas.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: OmniGymColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OmniGymColors.border),
            ),
            child: const Column(
              children: [
                Icon(Icons.receipt_long, size: 36, color: OmniGymColors.textSecondary),
                SizedBox(height: 8),
                Text('Sin facturas disponibles',
                    style: TextStyle(color: OmniGymColors.textSecondary)),
              ],
            ),
          );
        }
        return Column(
          children: facturas.take(5).map((f) => _FacturaTile(factura: f)).toList(),
        );
      },
    );
  }
}

class _FacturaTile extends StatelessWidget {
  const _FacturaTile({required this.factura});
  final Factura factura;

  @override
  Widget build(BuildContext context) {
    final date = factura.createdAt != null
        ? '${factura.createdAt!.day}/${factura.createdAt!.month}/${factura.createdAt!.year}'
        : factura.fecha ?? '';
    final vigente = factura.status == 'vigente';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: Row(
        children: [
          Icon(vigente ? Icons.check_circle : Icons.cancel,
              size: 18, color: vigente ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${factura.serie ?? ''}${factura.folio ?? ''} - ${factura.uuid.substring(0, 8)}',
                  style: const TextStyle(fontSize: 13, color: OmniGymColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(date,
                    style: const TextStyle(fontSize: 11, color: OmniGymColors.textSecondary)),
              ],
            ),
          ),
          Text('\$${(factura.total ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}

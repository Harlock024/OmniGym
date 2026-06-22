import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/models/member.dart';
import '../../core/models/payment.dart';
import '../../core/providers/providers.dart';
import '../memberships/memberships_screen.dart' show RegisterPaymentFromMember;

class MemberDetailDialog extends ConsumerWidget {
  const MemberDetailDialog({
    super.key,
    required this.member,
    required this.tenantId,
  });

  final Member member;
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(
      memberPaymentsProvider((tenantId: tenantId, memberId: member.id)),
    );

    final isActive = member.accessStatus == AccessStatus.active;
    final isExpired = member.expirationDate.isBefore(DateTime.now());
    final daysLeft = member.expirationDate.difference(DateTime.now()).inDays;

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isActive
                        ? Theme.of(context).colorScheme.primary.withAlpha(40)
                        : Theme.of(context).dividerTheme.color ?? OmniGymColors.border,
                    backgroundImage: member.photoUrl != null
                        ? NetworkImage(member.photoUrl!)
                        : null,
                    child: member.photoUrl == null
                        ? Text(
                            member.name[0].toUpperCase(),
                            style: TextStyle(
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          member.email,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(isActive: isActive),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close,
                        color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),

            // ── Membresía actual ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: _MembershipCard(
                member: member,
                isExpired: isExpired,
                daysLeft: daysLeft,
                onRegisterPayment: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => RegisterPaymentFromMember(
                      tenantId: tenantId,
                      member: member,
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),

            // ── Historial de pagos ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text(
                    'HISTORIAL DE PAGOS',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  paymentsAsync.whenOrNull(
                        data: (list) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withAlpha(25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${list.length}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ) ??
                      const SizedBox.shrink(),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: paymentsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13)),
                ),
                data: (payments) => payments.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long,
                                  size: 32,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                              SizedBox(height: 8),
                              Text(
                                'Sin pagos registrados',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: payments.length,
                        itemBuilder: (_, i) =>
                            _PaymentHistoryRow(payment: payments[i]),
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─── Tarjeta de membresía actual ──────────────────────────────────────────────

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.member,
    required this.isExpired,
    required this.daysLeft,
    required this.onRegisterPayment,
  });

  final Member member;
  final bool isExpired;
  final int daysLeft;
  final VoidCallback onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String statusText;

    if (isExpired) {
      statusColor = Theme.of(context).colorScheme.error;
      statusText = 'Vencida';
    } else if (daysLeft <= 7) {
      statusColor = Colors.orange;
      statusText = 'Vence en $daysLeft días';
    } else {
      statusColor = OmniGymColors.success;
      statusText = 'Vigente';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.card_membership_rounded,
                color: statusColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vence: ${_fmtDate(member.expirationDate)}',
                  style: TextStyle(
                    color: isExpired
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.payment, size: 14),
            label: const Text('Registrar pago'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: onRegisterPayment,
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─── Fila de historial ────────────────────────────────────────────────────────

class _PaymentHistoryRow extends StatelessWidget {
  const _PaymentHistoryRow({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final dt = payment.createdAt;
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: OmniGymColors.success.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check,
                color: OmniGymColors.success, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.planName ?? 'Plan',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                if (payment.reference != null)
                  Text(
                    'Ref: ${payment.reference}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            '\$${payment.amount % 1 == 0 ? payment.amount.toInt() : payment.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: OmniGymColors.success,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text(
              dateStr,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Badge de estado ──────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? OmniGymColors.success : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        isActive ? 'Activo' : 'Suspendido',
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

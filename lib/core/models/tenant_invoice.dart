import 'package:cloud_firestore/cloud_firestore.dart';

/// Factura del cobro SaaS B2B (la plataforma le cobra al gimnasio).
/// La escribe el Worker desde el webhook de Stripe; el cliente solo lee.
class TenantInvoice {
  const TenantInvoice({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    this.createdAt,
  });

  final String id;
  final double amount;
  final String currency;
  final String status; // paid, open, void, uncollectible…
  final DateTime? createdAt;

  static TenantInvoice fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    final ts = d['created_at'];
    return TenantInvoice(
      id: doc.id,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] as String?) ?? 'mxn',
      status: (d['status'] as String?) ?? 'unknown',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

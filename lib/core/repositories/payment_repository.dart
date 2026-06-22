import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/member.dart';
import '../models/payment.dart';

class PaymentRepository {
  final FirebaseFirestore _db;
  const PaymentRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      _db.collection('tenants').doc(tenantId).collection('payments');

  Stream<List<Payment>> watchByTenant(String tenantId, {int limit = 100}) =>
      _col(tenantId)
          .orderBy('created_at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(Payment.fromFirestore).toList());

  Stream<List<Payment>> watchByBranch(
    String tenantId,
    String branchId, {
    int limit = 100,
  }) =>
      _col(tenantId)
          .where('branch_id', isEqualTo: branchId)
          .orderBy('created_at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(Payment.fromFirestore).toList());

  Future<List<Payment>> fetchByPeriod(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final snap = await _col(tenantId)
        .where('created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('created_at',
            isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('created_at', descending: true)
        .get();
    return snap.docs.map(Payment.fromFirestore).toList();
  }

  Stream<List<Payment>> watchByMember(
    String tenantId,
    String memberId, {
    int limit = 50,
  }) =>
      _col(tenantId)
          .where('member_id', isEqualTo: memberId)
          .snapshots()
          .map((s) {
        final list = s.docs.map(Payment.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(limit).toList();
      });

  Future<String> registerPayment({
    required String tenantId,
    required String branchId,
    required String memberId,
    required String memberName,
    required String planId,
    required String planName,
    required int durationDays,
    required double amount,
    String? reference,
    String? notes,
  }) async {
    final memberRef = _db
        .collection('tenants')
        .doc(tenantId)
        .collection('members')
        .doc(memberId);

    final memberSnap = await memberRef.get();
    if (!memberSnap.exists) throw Exception('Socio no encontrado.');

    final member = Member.fromFirestore(memberSnap);
    final now = DateTime.now();
    final base = member.accessStatus == AccessStatus.active &&
            member.expirationDate.isAfter(now)
        ? member.expirationDate
        : now;
    final newExpiration = base.add(Duration(days: durationDays));

    String paymentId = '';
    await _db.runTransaction((tx) async {
      final paymentRef = _col(tenantId).doc();
      paymentId = paymentRef.id;
      tx.set(paymentRef, {
        'tenant_id': tenantId,
        'branch_id': branchId,
        'member_id': memberId,
        'member_name': memberName,
        'plan_id': planId,
        'plan_name': planName,
        'amount': amount,
        'currency': 'MXN',
        'status': 'completed',
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'created_at': FieldValue.serverTimestamp(),
      });
      tx.update(memberRef, {
        'plan_id': planId,
        'expiration_date': Timestamp.fromDate(newExpiration),
        'access_status': AccessStatus.active.name,
      });
    });
    return paymentId;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/membership_plan.dart';

class PlanRepository {
  final FirebaseFirestore _db;
  const PlanRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      _db.collection('tenants').doc(tenantId).collection('membership_plans');

  Stream<List<MembershipPlan>> watchActive(String tenantId) =>
      _col(tenantId)
          .where('is_active', isEqualTo: true)
          .orderBy('name')
          .snapshots()
          .map((s) => s.docs.map(MembershipPlan.fromFirestore).toList());

  Stream<List<MembershipPlan>> watchAll(String tenantId) =>
      _col(tenantId)
          .orderBy('name')
          .snapshots()
          .map((s) => s.docs.map(MembershipPlan.fromFirestore).toList());

  Future<MembershipPlan?> get(String tenantId, String planId) async {
    final snap = await _col(tenantId).doc(planId).get();
    return snap.exists ? MembershipPlan.fromFirestore(snap) : null;
  }

  Future<String> create(MembershipPlan plan) async {
    final json = plan.toJson()..remove('id');
    json['created_at'] = FieldValue.serverTimestamp();
    final ref = await _col(plan.tenantId).add(json);
    return ref.id;
  }

  Future<void> update(MembershipPlan plan) async {
    final json = plan.toJson()
      ..remove('id')
      ..remove('tenant_id')
      ..remove('created_at');
    await _col(plan.tenantId).doc(plan.id).update(json);
  }

  Future<void> setActive(
    String tenantId,
    String planId, {
    required bool isActive,
  }) async {
    await _col(tenantId).doc(planId).update({'is_active': isActive});
  }
}

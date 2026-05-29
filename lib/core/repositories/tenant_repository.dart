import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tenant.dart';

class TenantRepository {
  final FirebaseFirestore _db;

  const TenantRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('tenants');

  Stream<Tenant?> watch(String tenantId) {
    return _col.doc(tenantId).snapshots().map(
          (snap) => snap.exists ? Tenant.fromFirestore(snap) : null,
        );
  }

  Future<Tenant?> get(String tenantId) async {
    final snap = await _col.doc(tenantId).get();
    return snap.exists ? Tenant.fromFirestore(snap) : null;
  }

  Stream<List<Tenant>> watchAll() {
    return _col
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(Tenant.fromFirestore).toList());
  }

  Future<String> create(Tenant tenant) async {
    final json = tenant.toJson()..remove('id');
    json['created_at'] = FieldValue.serverTimestamp();
    final ref = await _col.add(json);
    return ref.id;
  }

  Future<void> updateSettings(String tenantId, TenantSettings settings) async {
    await _col.doc(tenantId).update({'settings': settings.toJson()});
  }

  Future<void> updateName(String tenantId, String name) async {
    await _col.doc(tenantId).update({'name': name});
  }

  Future<void> updateSubscriptionStatus(
    String tenantId,
    SubscriptionStatus status,
  ) async {
    await _col.doc(tenantId).update({
      'subscription_status': status.name,
    });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/member.dart';

class MemberRepository {
  final FirebaseFirestore _db;

  const MemberRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      _db.collection('tenants').doc(tenantId).collection('members');

  Stream<List<Member>> watchAll(String tenantId) {
    return _col(tenantId).orderBy('name').snapshots().map(
          (snap) => snap.docs.map(Member.fromFirestore).toList(),
        );
  }

  Stream<List<Member>> watchByBranch(String tenantId, String branchId) {
    return _col(tenantId)
        .where('allowed_branches', arrayContains: branchId)
        .snapshots()
        .map((snap) => snap.docs.map(Member.fromFirestore).toList());
  }

  Future<Member?> get(String tenantId, String memberId) async {
    final snap = await _col(tenantId).doc(memberId).get();
    return snap.exists ? Member.fromFirestore(snap) : null;
  }

  Future<Member?> getByQrToken(String tenantId, String qrToken) async {
    final snap = await _col(tenantId)
        .where('qr_token', isEqualTo: qrToken)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Member.fromFirestore(snap.docs.first);
  }

  Future<String> create(Member member) async {
    final json = member.toJson()..remove('id');
    json['created_at'] = FieldValue.serverTimestamp();
    final ref = await _col(member.tenantId).add(json);
    return ref.id;
  }

  Stream<int> watchActiveCount(String tenantId, String branchId) {
    return _col(tenantId)
        .where('allowed_branches', arrayContains: branchId)
        .where('access_status', isEqualTo: AccessStatus.active.name)
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<int> watchActiveTenantCount(String tenantId) {
    return _col(tenantId)
        .where('access_status', isEqualTo: AccessStatus.active.name)
        .where('expiration_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()))
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<int> watchExpiringCount(String tenantId, {int withinDays = 7}) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return _col(tenantId)
        .where('access_status', isEqualTo: AccessStatus.active.name)
        .where('expiration_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('expiration_date',
            isLessThanOrEqualTo: Timestamp.fromDate(cutoff))
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<int> watchNewThisMonth(String tenantId) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    return _col(tenantId)
        .where('created_at',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .snapshots()
        .map((snap) => snap.size);
  }

  Future<void> update(String tenantId, Member member) async {
    final json = member.toJson()..remove('id')..remove('tenant_id');
    await _col(tenantId).doc(member.id).update(json);
  }

  Future<void> updateAccessStatus(
    String tenantId,
    String memberId,
    AccessStatus status,
  ) async {
    await _col(tenantId).doc(memberId).update({
      'access_status': status.name,
    });
  }

  Future<void> logCheckIn({
    required String tenantId,
    required String branchId,
    required Map<String, dynamic> checkInData,
  }) async {
    await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('branches')
        .doc(branchId)
        .collection('check_ins')
        .add({
      ...checkInData,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

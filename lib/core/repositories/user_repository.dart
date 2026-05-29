import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

class UserRepository {
  final FirebaseFirestore _db;

  const UserRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users');

  Future<void> create(AppUser user) async {
    final json = user.toJson()..remove('id');
    json['created_at'] = FieldValue.serverTimestamp();
    await _col.doc(user.id).set(json);
  }

  Future<AppUser?> get(String uid) async {
    final snap = await _col.doc(uid).get();
    return snap.exists ? AppUser.fromFirestore(snap) : null;
  }

  Stream<AppUser?> watch(String uid) {
    return _col.doc(uid).snapshots().map(
          (snap) => snap.exists ? AppUser.fromFirestore(snap) : null,
        );
  }

  Stream<List<AppUser>> watchByTenant(String tenantId) {
    return _col
        .where('tenant_id', isEqualTo: tenantId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Stream<List<AppUser>> watchAll() {
    return _col
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromFirestore).toList());
  }

  Future<void> updateStatus(String uid, UserStatus status) async {
    await _col.doc(uid).update({'status': status.name});
  }

  Future<void> updateRole(String uid, UserRole role) async {
    await _col.doc(uid).update({'role': role.name});
  }

  Future<void> updateBranchId(String uid, String? branchId) async {
    await _col.doc(uid).update({'branch_id': branchId});
  }

  Future<void> updateTenantAndRole(
    String uid, {
    required String? tenantId,
    required UserRole role,
  }) async {
    await _col.doc(uid).update({
      'tenant_id': tenantId,
      'role': role.name,
    });
  }

  Future<void> updatePermissions(
    String uid,
    Map<String, bool> permissions,
  ) async {
    await _col.doc(uid).update({'permissions': permissions});
  }

  Future<void> updateProfile(
    String uid, {
    required String name,
    String? phone,
    String? photoUrl,
  }) async {
    await _col.doc(uid).update({
      'name': name,
      'phone': phone,
      'photo_url': photoUrl,
    });
  }

  Future<void> updateNotificationPrefs(
    String uid,
    NotificationPrefs prefs,
  ) async {
    await _col.doc(uid).update({
      'notification_prefs': prefs.toJson(),
    });
  }

  Future<void> delete(String uid) async {
    await _col.doc(uid).delete();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/branch.dart';

class BranchRepository {
  final FirebaseFirestore _db;

  const BranchRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      _db.collection('tenants').doc(tenantId).collection('branches');

  Stream<List<Branch>> watchAll(String tenantId) {
    return _col(tenantId).orderBy('name').snapshots().map(
          (snap) => snap.docs.map(Branch.fromFirestore).toList(),
        );
  }

  Stream<Branch?> watch(String tenantId, String branchId) {
    return _col(tenantId).doc(branchId).snapshots().map(
          (snap) => snap.exists ? Branch.fromFirestore(snap) : null,
        );
  }

  Future<Branch?> get(String tenantId, String branchId) async {
    final snap = await _col(tenantId).doc(branchId).get();
    return snap.exists ? Branch.fromFirestore(snap) : null;
  }

  Future<String> create(Branch branch) async {
    final json = _toMap(branch)..remove('id');
    json['created_at'] = FieldValue.serverTimestamp();
    final ref = await _col(branch.tenantId).add(json);
    return ref.id;
  }

  Future<void> setActive(
    String tenantId,
    String branchId, {
    required bool isActive,
  }) async {
    await _col(tenantId).doc(branchId).update({'is_active': isActive});
  }

  Stream<int> watchTodayCheckInCount(String tenantId, String branchId) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    return _col(tenantId)
        .doc(branchId)
        .collection('check_ins')
        .where('timestamp', isGreaterThanOrEqualTo: todayMidnight)
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<int> watchRangeCheckInCount(
    String tenantId,
    String branchId,
    DateTime from,
    DateTime to,
  ) {
    final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return _col(tenantId)
        .doc(branchId)
        .collection('check_ins')
        .where('timestamp', isGreaterThanOrEqualTo: from)
        .where('timestamp', isLessThanOrEqualTo: endOfDay)
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<List<({DateTime day, int count})>> watchDailyCheckIns(
    String tenantId,
    String branchId, {
    int days = 7,
  }) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return _col(tenantId)
        .doc(branchId)
        .collection('check_ins')
        .where('timestamp', isGreaterThanOrEqualTo: from)
        .snapshots()
        .map((snap) {
      final counts = <String, int>{};
      for (var i = 0; i < days; i++) {
        counts[_dayKey(from.add(Duration(days: i)))] = 0;
      }
      for (final doc in snap.docs) {
        final ts = doc.data()['timestamp'];
        if (ts == null) continue;
        final key = _dayKey((ts as Timestamp).toDate());
        if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
      }
      return List.generate(
        days,
        (i) {
          final day = from.add(Duration(days: i));
          return (day: day, count: counts[_dayKey(day)] ?? 0);
        },
      );
    });
  }

  Stream<List<Map<String, dynamic>>> watchRecentCheckIns(
    String tenantId,
    String branchId, {
    int limit = 15,
  }) {
    return _col(tenantId)
        .doc(branchId)
        .collection('check_ins')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> update(Branch branch) async {
    final json = _toMap(branch)..remove('id')..remove('tenant_id');
    await _col(branch.tenantId).doc(branch.id).update(json);
  }

  // Serializa manualmente los nested objects para evitar que Firestore reciba
  // instancias Freezed en lugar de Maps planos.
  Map<String, dynamic> _toMap(Branch branch) {
    final map = <String, dynamic>{
      'id': branch.id,
      'tenant_id': branch.tenantId,
      'name': branch.name,
      'is_active': branch.isActive,
      'manager_id': branch.managerId,
      'address': branch.address == null
          ? null
          : {
              'street': branch.address!.street,
              'city': branch.address!.city,
              'state': branch.address!.state,
              'postal_code': branch.address!.postalCode,
              'colonia': branch.address!.colonia,
              'municipality': branch.address!.municipality,
              'country': branch.address!.country,
            },
      'location': branch.location == null
          ? null
          : {
              'latitude': branch.location!.latitude,
              'longitude': branch.location!.longitude,
              'radius_meters': branch.location!.radiusMeters,
            },
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }
}

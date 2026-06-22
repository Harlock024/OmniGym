import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/factura.dart';

class FacturaRepository {
  final FirebaseFirestore _db;
  const FacturaRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      _db.collection('tenants').doc(tenantId).collection('facturas');

  Stream<List<Factura>> watchByTenant(String tenantId) =>
      _col(tenantId)
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
          .map((s) {
        final docs = s.docs;
        return docs.map((d) {
          // const Factura.fromFirestore no existe en freezed sin fromFirestore
          return Factura.fromJson({...d.data(), 'id': d.id});
        }).toList();
      });

  Stream<List<Factura>> watchByReceptor(String tenantId, String rfc) =>
      _col(tenantId)
          .where('receptor_rfc', isEqualTo: rfc)
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
          .map((s) {
        final docs = s.docs;
        return docs.map((d) {
          return Factura.fromJson({...d.data(), 'id': d.id});
        }).toList();
      });

  Future<List<Factura>> fetchPending() async {
    final membersSnap = await _db
        .collectionGroup('facturas')
        .where('status', isEqualTo: 'vigente')
        .get();
    return membersSnap.docs
        .map((d) => Factura.fromJson({...d.data(), 'id': d.id}))
        .toList();
  }
}

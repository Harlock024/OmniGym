import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/tenant_invoice.dart';

void main() {
  group('TenantInvoice', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('fromFirestore parsea todos los campos correctamente', () async {
      await firestore
          .collection('tenant_invoices')
          .doc('inv_001')
          .set({
        'amount': 499.0,
        'currency': 'mxn',
        'status': 'paid',
        'created_at': Timestamp.fromDate(DateTime(2025, 6, 1)),
      });

      final snap = await firestore
          .collection('tenant_invoices')
          .doc('inv_001')
          .get();

      final invoice = TenantInvoice.fromFirestore(snap);

      expect(invoice.id, 'inv_001');
      expect(invoice.amount, 499.0);
      expect(invoice.currency, 'mxn');
      expect(invoice.status, 'paid');
      expect(invoice.createdAt, DateTime(2025, 6, 1));
    });

    test('fromFirestore maneja documento con campos minimos', () async {
      await firestore
          .collection('tenant_invoices')
          .doc('inv_min')
          .set({});

      final snap = await firestore
          .collection('tenant_invoices')
          .doc('inv_min')
          .get();

      final invoice = TenantInvoice.fromFirestore(snap);

      expect(invoice.id, 'inv_min');
      expect(invoice.amount, 0);
      expect(invoice.currency, 'mxn');
      expect(invoice.status, 'unknown');
      expect(invoice.createdAt, isNull);
    });

    test('fromFirestore usa defaults para campos ausentes', () async {
      await firestore
          .collection('tenant_invoices')
          .doc('inv_defaults')
          .set({
        'status': 'open',
      });

      final snap = await firestore
          .collection('tenant_invoices')
          .doc('inv_defaults')
          .get();

      final invoice = TenantInvoice.fromFirestore(snap);

      expect(invoice.amount, 0);
      expect(invoice.currency, 'mxn');
    });
  });
}

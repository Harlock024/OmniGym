import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'payment.freezed.dart';
part 'payment.g.dart';

enum PaymentStatus { pending, completed, refunded, failed }

@freezed
class Payment with _$Payment {
  const factory Payment({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    @JsonKey(name: 'branch_id') required String branchId,
    @JsonKey(name: 'member_id') required String memberId,
    @JsonKey(name: 'member_name') String? memberName,
    @JsonKey(name: 'plan_id') required String planId,
    @JsonKey(name: 'plan_name') String? planName,
    required double amount,
    @Default('MXN') String currency,
    required PaymentStatus status,
    @JsonKey(name: 'created_at')
    @TimestampConverter()
    required DateTime createdAt,
    String? reference,
    String? notes,
    @JsonKey(name: 'factura_uuid') String? facturaUuid,
    @JsonKey(name: 'facturado_at')
    @NullableTimestampConverter()
    DateTime? facturadoAt,
  }) = _Payment;

  factory Payment.fromJson(Map<String, dynamic> json) =>
      _$PaymentFromJson(json);

  static Payment fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Payment.fromJson({...doc.data()!, 'id': doc.id});
  }
}

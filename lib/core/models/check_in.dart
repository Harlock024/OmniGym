import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'check_in.freezed.dart';
part 'check_in.g.dart';

enum CheckInMethod { qr, gps, manual }

enum CheckInResult { granted, denied }

@freezed
abstract class CheckIn with _$CheckIn {
  const factory CheckIn({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    @JsonKey(name: 'branch_id') required String branchId,
    @JsonKey(name: 'member_id') required String memberId,
    required CheckInMethod method,
    required CheckInResult result,
    @TimestampConverter() required DateTime timestamp,
    @JsonKey(name: 'denial_reason') String? denialReason,
    double? latitude,
    double? longitude,
  }) = _CheckIn;

  factory CheckIn.fromJson(Map<String, dynamic> json) =>
      _$CheckInFromJson(json);

  static CheckIn fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return CheckIn.fromJson({...doc.data()!, 'id': doc.id});
  }
}

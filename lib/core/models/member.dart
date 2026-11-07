import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'member.freezed.dart';
part 'member.g.dart';

enum AccessStatus { active, suspended }

@freezed
abstract class Member with _$Member {
  const factory Member({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    required String name,
    required String email,
    @JsonKey(name: 'access_status') required AccessStatus accessStatus,
    @JsonKey(name: 'allowed_branches') required List<String> allowedBranches,
    @JsonKey(name: 'qr_token') required String qrToken,
    @JsonKey(name: 'expiration_date')
    @TimestampConverter()
    required DateTime expirationDate,
    @JsonKey(name: 'photo_url') String? photoUrl,
    String? phone,
    @JsonKey(name: 'plan_id') String? planId,
    @JsonKey(name: 'created_at')
    @NullableTimestampConverter()
    DateTime? createdAt,
  }) = _Member;

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);

  static Member fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Member.fromJson({...doc.data()!, 'id': doc.id});
  }
}

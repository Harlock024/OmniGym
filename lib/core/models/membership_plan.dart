import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'membership_plan.freezed.dart';
part 'membership_plan.g.dart';

@freezed
abstract class MembershipPlan with _$MembershipPlan {
  const factory MembershipPlan({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    // null = plan global (aplica a todas las sucursales del tenant)
    @JsonKey(name: 'branch_id') String? branchId,
    required String name,
    required double price,
    @Default('MXN') String currency,
    @JsonKey(name: 'duration_days') required int durationDays,
    // Catálogos SAT (se completan en Epic SAT Core)
    @JsonKey(name: 'sat_product_key') String? satProductKey,
    @JsonKey(name: 'sat_unit_key') String? satUnitKey,
    @Default(true) bool isActive,
    @JsonKey(name: 'created_at')
    @NullableTimestampConverter()
    DateTime? createdAt,
  }) = _MembershipPlan;

  factory MembershipPlan.fromJson(Map<String, dynamic> json) =>
      _$MembershipPlanFromJson(json);

  static MembershipPlan fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return MembershipPlan.fromJson({...doc.data()!, 'id': doc.id});
  }
}

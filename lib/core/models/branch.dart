import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'branch.freezed.dart';
part 'branch.g.dart';

@freezed
abstract class Branch with _$Branch {
  const factory Branch({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    required String name,
    @JsonKey(name: 'is_active') required bool isActive,
    @JsonKey(name: 'manager_id') String? managerId,
    BranchAddress? address,
    BranchLocation? location,
    @JsonKey(name: 'created_at')
    @NullableTimestampConverter()
    DateTime? createdAt,
  }) = _Branch;

  factory Branch.fromJson(Map<String, dynamic> json) => _$BranchFromJson(json);

  static Branch fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Branch.fromJson({...doc.data()!, 'id': doc.id});
  }
}

@freezed
abstract class BranchAddress with _$BranchAddress {
  const factory BranchAddress({
    required String street,
    required String city,
    required String state,
    @JsonKey(name: 'postal_code') required String postalCode,
    String? colonia,
    String? municipality,
    @Default('MX') String country,
  }) = _BranchAddress;

  factory BranchAddress.fromJson(Map<String, dynamic> json) =>
      _$BranchAddressFromJson(json);
}

@freezed
abstract class BranchLocation with _$BranchLocation {
  const factory BranchLocation({
    required double latitude,
    required double longitude,
    @JsonKey(name: 'radius_meters') @Default(100) int radiusMeters,
  }) = _BranchLocation;

  factory BranchLocation.fromJson(Map<String, dynamic> json) =>
      _$BranchLocationFromJson(json);
}

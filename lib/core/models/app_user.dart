import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

enum UserRole { superuser, owner, staff }

enum UserStatus { active, suspended }

@freezed
class NotificationPrefs with _$NotificationPrefs {
  const factory NotificationPrefs({
    @Default(true) @JsonKey(name: 'check_ins') bool checkIns,
    @Default(true) @JsonKey(name: 'payments') bool payments,
    @Default(true) @JsonKey(name: 'member_expiry') bool memberExpiry,
    @Default(false) @JsonKey(name: 'marketing') bool marketing,
  }) = _NotificationPrefs;

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) =>
      _$NotificationPrefsFromJson(json);
}

@freezed
class AppUser with _$AppUser {
  const factory AppUser({
    required String id,
    @JsonKey(name: 'tenant_id') String? tenantId,
    @JsonKey(name: 'branch_id') String? branchId,
    required String name,
    required String email,
    String? phone,
    @JsonKey(name: 'photo_url') String? photoUrl,
    required UserRole role,
    required UserStatus status,
    @JsonKey(name: 'notification_prefs')
    @Default(NotificationPrefs())
    NotificationPrefs notificationPrefs,
    @JsonKey(name: 'permissions')
    @Default(<String, bool>{})
    Map<String, bool> permissions,
    @JsonKey(name: 'created_at')
    @NullableTimestampConverter()
    DateTime? createdAt,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) =>
      _$AppUserFromJson(json);

  static AppUser fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromJson({...doc.data()!, 'id': doc.id});
  }
}

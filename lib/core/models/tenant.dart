import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'converters.dart';

part 'tenant.freezed.dart';
part 'tenant.g.dart';

enum SubscriptionStatus { active, suspended, cancelled }

@freezed
class Tenant with _$Tenant {
  const factory Tenant({
    required String id,
    required String slug,
    required String name,
    @JsonKey(name: 'subscription_status')
    required SubscriptionStatus subscriptionStatus,
    @JsonKey(name: 'billing_cycle_end')
    @TimestampConverter()
    required DateTime billingCycleEnd,
    required TenantSettings settings,
    @JsonKey(name: 'created_at')
    @NullableTimestampConverter()
    DateTime? createdAt,
  }) = _Tenant;

  factory Tenant.fromJson(Map<String, dynamic> json) => _$TenantFromJson(json);

  static Tenant fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Tenant.fromJson({...doc.data()!, 'id': doc.id});
  }
}

@freezed
class TenantSettings with _$TenantSettings {
  const factory TenantSettings({
    // ── Branding ──────────────────────────────────────────────────────────────
    @JsonKey(name: 'logo_url') String? logoUrl,
    @JsonKey(name: 'primary_color') @Default('#2563EB') String primaryColor,

    // ── Datos generales ───────────────────────────────────────────────────────
    String? address,
    @Default('MX') String country,
    String? state,
    String? municipality,
    @JsonKey(name: 'postal_code') String? postalCode,
    @JsonKey(name: 'contact_name') String? contactName,
    String? phone,
    String? email,

    // ── Datos fiscales ────────────────────────────────────────────────────────
    String? rfc,
    @JsonKey(name: 'razon_social') String? razonSocial,
    String? giro,
    @JsonKey(name: 'tipo_comprobante') @Default('I') String tipoComprobante,
    @JsonKey(name: 'regimen_fiscal') String? regimenFiscal,
    String? serie,
    @JsonKey(name: 'num_aprobacion') String? numAprobacion,
    @JsonKey(name: 'anio_aprobacion') String? anioAprobacion,
    @JsonKey(name: 'folio_inicial') int? folioInicial,
    @JsonKey(name: 'folio_final') int? folioFinal,
    @JsonKey(name: 'folio_actual') int? folioActual,
    @JsonKey(name: 'fecha_vencimiento')
    @NullableTimestampConverter()
    DateTime? fechaVencimiento,

    // ── Certificados SAT ──────────────────────────────────────────────────────
    // Datos en base64 (guardados en Firestore hasta integrar R2)
    @JsonKey(name: 'cert_cer_data') String? certCerData,
    @JsonKey(name: 'cert_key_data') String? certKeyData,
    @JsonKey(name: 'cert_cer_name') String? certCerName,
    @JsonKey(name: 'cert_key_name') String? certKeyName,
    // URLs para cuando se migre a R2 (vacío por ahora)
    @JsonKey(name: 'cert_cer_url') String? certCerUrl,
    @JsonKey(name: 'cert_key_url') String? certKeyUrl,
  }) = _TenantSettings;

  factory TenantSettings.fromJson(Map<String, dynamic> json) =>
      _$TenantSettingsFromJson(json);
}

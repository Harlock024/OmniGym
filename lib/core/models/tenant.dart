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
    // Cobro SaaS B2B (lo escribe el worker vía Stripe webhook / cron).
    @JsonKey(name: 'past_due') @Default(false) bool pastDue,
    @JsonKey(name: 'stripe_customer_id') String? stripeCustomerId,
    @JsonKey(name: 'package_price_id') String? packagePriceId,
    // Estado de la suscripción Stripe: 'trialing' | 'active' | 'past_due' |
    // 'canceled' … null = el gym nunca ha iniciado su prueba/plan.
    @JsonKey(name: 'stripe_subscription_status') String? stripeSubscriptionStatus,
    @JsonKey(name: 'trial_used') @Default(false) bool trialUsed,
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
    @JsonKey(name: 'secondary_color') @Default('#03DAC6') String secondaryColor,
    @JsonKey(name: 'theme_mode') @Default('system') String themeMode,

    // ── Datos generales ───────────────────────────────────────────────────────
    String? address,
    @Default('MX') String country,
    String? state,
    String? municipality,
    String? colonia,
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

    // ── Configuracion CFDI 4.0 ─────────────────────────────────────────────────
    @JsonKey(name: 'metodo_pago') @Default('PUE') String metodoPago,
    @JsonKey(name: 'forma_pago') @Default('01') String formaPago,
    @JsonKey(name: 'uso_cfdi') @Default('G03') String usoCFDI,

    // ── Certificados SAT ──────────────────────────────────────────────────────
    // Los archivos viven en Cloudflare R2; en Firestore solo guardamos las URLs,
    // los nombres y la bandera de subida. La contraseña del CSD nunca se almacena.
    @JsonKey(name: 'cert_cer_url') String? certCerUrl,
    @JsonKey(name: 'cert_key_url') String? certKeyUrl,
    @JsonKey(name: 'cert_cer_name') String? certCerName,
    @JsonKey(name: 'cert_key_name') String? certKeyName,
    @JsonKey(name: 'csd_uploaded') @Default(false) bool csdUploaded,
    // Legacy: datos en base64 (solo lectura para tenants previos a la migración R2)
    @JsonKey(name: 'cert_cer_data') String? certCerData,
    @JsonKey(name: 'cert_key_data') String? certKeyData,
  }) = _TenantSettings;

  factory TenantSettings.fromJson(Map<String, dynamic> json) =>
      _$TenantSettingsFromJson(json);
}

import 'package:freezed_annotation/freezed_annotation.dart';
import 'converters.dart';

part 'factura.freezed.dart';
part 'factura.g.dart';

@freezed
class Factura with _$Factura {
  const factory Factura({
    required String id,
    @JsonKey(name: 'tenant_id') required String tenantId,
    required String uuid,
    String? serie,
    String? folio,
    String? fecha,
    @JsonKey(name: 'fecha_timbrado') String? fechaTimbrado,
    @JsonKey(name: 'emisor_rfc') String? emisorRfc,
    @JsonKey(name: 'receptor_rfc') String? receptorRfc,
    @JsonKey(name: 'receptor_nombre') String? receptorNombre,
    double? total,
    String? moneda,
    String? tipo,
    String? status,
    @JsonKey(name: 'payment_id') String? paymentId,
    @JsonKey(name: 'facturapi_invoice_id') String? facturapiInvoiceId,
    @JsonKey(name: 'xml_timbrado') String? xmlTimbrado,
    @JsonKey(name: 'created_at')
    @NullableTimestampConverter()
    DateTime? createdAt,
  }) = _Factura;

  factory Factura.fromJson(Map<String, dynamic> json) =>
      _$FacturaFromJson(json);
}

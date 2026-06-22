import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class WorkerService {
  static const _base = String.fromEnvironment(
    'WORKER_BASE_URL',
    defaultValue: 'https://omni-gym.hadith024.workers.dev',
  );
  static const _secret = String.fromEnvironment(
    'R2_UPLOAD_SECRET',
    defaultValue: 'omni-r2-2025-dev',
  );

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer $_secret',
        'Content-Type': 'application/json',
      };

  /// Asigna custom claims a un usuario existente de Firebase Auth.
  static Future<void> setClaims({
    required String uid,
    required String role,
    required String tenantId,
    String? branchId,
  }) async {
    final body = <String, dynamic>{
      'uid': uid,
      'role': role,
      'tenant_id': tenantId,
    };
    if (branchId != null) body['branch_id'] = branchId;

    final res = await http.post(
      Uri.parse('$_base/set-claims'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception('set-claims failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Crea un usuario en Firebase Auth, asigna claims y envía email de contraseña.
  /// Devuelve el UID del nuevo usuario.
  static Future<String> createStaff({
    required String name,
    required String email,
    required String role,
    required String tenantId,
    String? branchId,
    String? gymName,
    String? csdCargo,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'role': role,
      'tenant_id': tenantId,
    };
    if (branchId != null) body['branch_id'] = branchId;
    if (gymName != null && gymName.isNotEmpty) body['gymName'] = gymName;
    if (csdCargo != null && csdCargo.isNotEmpty) body['csd_cargo'] = csdCargo;

    final res = await http.post(
      Uri.parse('$_base/create-staff'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (res.statusCode == 409) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw StaffAlreadyExistsException(
          data['error'] as String? ?? 'El correo ya está registrado.');
    }

    if (res.statusCode != 200) {
      throw Exception('create-staff failed (${res.statusCode}): ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['uid'] as String;
  }

  /// Crea una sesión de Stripe Checkout (suscripción) y devuelve la URL de pago.
  static Future<String> createCheckout({
    required String tenantId,
    required String priceId,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final body = <String, dynamic>{'tenantId': tenantId, 'priceId': priceId};
    if (successUrl != null) body['successUrl'] = successUrl;
    if (cancelUrl != null) body['cancelUrl'] = cancelUrl;
    final res = await http.post(
      Uri.parse('$_base/billing/checkout'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('checkout failed (${res.statusCode}): ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['url'] as String;
  }

  /// Abre el Customer Portal de Stripe; devuelve la URL.
  static Future<String> billingPortal({
    required String tenantId,
    String? returnUrl,
  }) async {
    final body = <String, dynamic>{'tenantId': tenantId};
    if (returnUrl != null) body['returnUrl'] = returnUrl;
    final res = await http.post(
      Uri.parse('$_base/billing/portal'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('portal failed (${res.statusCode}): ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['url'] as String;
  }

  /// Crea un paquete de suscripción: producto + precio en Stripe y doc Firestore.
  static Future<void> createPackage({
    required String name,
    required double price,
    int? branches,
    int? checkins,
    int? staff,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/billing/packages'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'price': price,
        'limits': {'branches': branches, 'checkins': checkins, 'staff': staff},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('createPackage failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Actualiza un paquete (nombre/precio/activo/límites). Cambiar el precio crea
  /// un nuevo precio en Stripe y archiva el anterior.
  static Future<void> updatePackage({
    required String id,
    String? name,
    double? price,
    bool? active,
    int? branches,
    int? checkins,
    int? staff,
  }) async {
    final body = <String, dynamic>{'id': id};
    if (name != null) body['name'] = name;
    if (price != null) body['price'] = price;
    if (active != null) body['active'] = active;
    final limits = <String, dynamic>{};
    if (branches != null) limits['branches'] = branches;
    if (checkins != null) limits['checkins'] = checkins;
    if (staff != null) limits['staff'] = staff;
    if (limits.isNotEmpty) body['limits'] = limits;

    final res = await http.post(
      Uri.parse('$_base/billing/packages/update'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('updatePackage failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Consulta el catálogo postal SEPOMEX (Cloudflare D1) por código postal.
  /// Devuelve null si el CP no existe o falla la consulta (el catálogo es ayuda,
  /// no debe bloquear el formulario).
  static Future<PostalLookup?> lookupPostalCode(String cp) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/catalogs/postal?cp=$cp'),
        headers: _headers,
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['found'] != true) return null;
      return PostalLookup(
        estado: data['estado'] as String?,
        municipio: data['municipio'] as String?,
        ciudad: data['ciudad'] as String?,
        colonias: (data['colonias'] as List<dynamic>? ?? [])
            .map((c) => (c as Map<String, dynamic>)['nombre'] as String)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Elimina un operador: borra su cuenta de Firebase Auth y el doc /users/{uid}.
  static Future<void> deleteStaff(String uid) async {
    final res = await http.post(
      Uri.parse('$_base/delete-staff'),
      headers: _headers,
      body: jsonEncode({'uid': uid}),
    );
    if (res.statusCode != 200) {
      throw Exception('delete-staff failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Busca direcciones vía Nominatim (OpenStreetMap) a través del worker.
  /// Devuelve hasta 5 resultados con coordenadas para centrar el mapa.
  static Future<List<GeocodeResult>> searchAddress(String query) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/geocode/search?q=${Uri.encodeComponent(query)}'),
        headers: _headers,
      );
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['results'] as List<dynamic>? ?? [])
          .map((r) => GeocodeResult(
                displayName:
                    (r as Map<String, dynamic>)['displayName'] as String,
                lat: (r['lat'] as num).toDouble(),
                lng: (r['lng'] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Facturación CFDI ──────────────────────────────────────────────────────

  static Future<FacturacionValidacion> validarFacturacion(String tenantId) async {
    final res = await http.get(
      Uri.parse('$_base/facturacion/validate?tenantId=$tenantId'),
      headers: _headers,
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return FacturacionValidacion(
      ok: data['ok'] as bool,
      errors: (data['errors'] as List<dynamic>?)
              ?.map((e) => ValidacionError(
                    campo: (e as Map<String, dynamic>)['campo'] as String,
                    mensaje: e['mensaje'] as String,
                  ))
              .toList() ??
          [],
    );
  }

  static Future<FacturacionResultado> timbrarFactura({
    required String tenantId,
    required List<Map<String, dynamic>> conceptos,
    String? rfc,
    String? nombre,
    String? codigoPostal,
    String? regimenFiscal,
    String? usoCFDI,
    String? paymentId,
  }) async {
    final body = <String, dynamic>{'tenantId': tenantId, 'conceptos': conceptos};
    if (rfc != null) body['rfc'] = rfc;
    if (nombre != null) body['nombre'] = nombre;
    if (codigoPostal != null) body['codigo_postal'] = codigoPostal;
    if (regimenFiscal != null) body['regimen_fiscal'] = regimenFiscal;
    if (usoCFDI != null) body['uso_cfdi'] = usoCFDI;
    if (paymentId != null) body['paymentId'] = paymentId;

    final res = await http.post(
      Uri.parse('$_base/facturacion/timbrar'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return FacturacionResultado(
      ok: data['ok'] as bool? ?? false,
      uuid: data['uuid'] as String?,
      mensaje: data['mensaje'] as String?,
      errors: (data['errors'] as List<dynamic>?)
              ?.map((e) => ValidacionError(
                    campo: (e as Map<String, dynamic>)['campo'] as String,
                    mensaje: e['mensaje'] as String,
                  ))
              .toList(),
    );
  }

  static Future<FacturacionResultado> cancelarFactura({
    required String tenantId,
    required String uuid,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/facturacion/cancelar'),
      headers: _headers,
      body: jsonEncode({'tenantId': tenantId, 'uuid': uuid}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return FacturacionResultado(
      ok: data['ok'] as bool? ?? false,
      uuid: uuid,
      mensaje: data['error'] as String?,
    );
  }

  static Future<String?> descargarXml({
    required String tenantId,
    required String uuid,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/facturacion/invoice?uuid=$uuid&tenantId=$tenantId&format=xml'),
        headers: _headers,
      );
      if (res.statusCode == 200) return res.body;
    } catch (_) {}
    return null;
  }

  static String urlPdf({required String tenantId, required String uuid}) {
    return '$_base/facturacion/invoice?uuid=$uuid&tenantId=$tenantId&format=pdf';
  }

  static Future<Uint8List?> descargarPdf({
    required String tenantId,
    required String uuid,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/facturacion/invoice?uuid=$uuid&tenantId=$tenantId&format=pdf'),
        headers: _headers,
      );
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> obtenerFactura({
    required String tenantId,
    required String uuid,
  }) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/facturacion/invoice?uuid=$uuid&tenantId=$tenantId'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> enviarFacturaEmail({
    required String tenantId,
    required String uuid,
    required String email,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/facturacion/enviar-email'),
        headers: _headers,
        body: jsonEncode({
          'tenantId': tenantId,
          'uuid': uuid,
          'email': email,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['ok'] == true;
      }
    } catch (_) {}
    return false;
  }
}

class PostalLookup {
  const PostalLookup({
    this.estado,
    this.municipio,
    this.ciudad,
    this.colonias = const [],
  });
  final String? estado;
  final String? municipio;
  final String? ciudad;
  final List<String> colonias;
}

class GeocodeResult {
  const GeocodeResult({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
  final String displayName;
  final double lat;
  final double lng;
}

class StaffAlreadyExistsException implements Exception {
  const StaffAlreadyExistsException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Facturación ──────────────────────────────────────────────────────────────

class FacturacionValidacion {
  const FacturacionValidacion({required this.ok, this.errors = const []});
  final bool ok;
  final List<ValidacionError> errors;
}

class ValidacionError {
  const ValidacionError({required this.campo, required this.mensaje});
  final String campo;
  final String mensaje;
}

class FacturacionResultado {
  const FacturacionResultado({
    required this.ok,
    this.uuid,
    this.mensaje,
    this.errors,
  });
  final bool ok;
  final String? uuid;
  final String? mensaje;
  final List<ValidacionError>? errors;
}

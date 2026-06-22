// Conector REST para Facturapi.io
// Facturapi maneja XML, firma, y timbrado internamente.
// Solo enviamos JSON con los datos del CFDI.

class FacturapiConnector {
  constructor(config) {
    this.baseUrl = config.baseUrl ?? 'https://www.facturapi.io/v2';
    this.apiKey = config.apiKey ?? '';
    this.timeout = config.timeout ?? 30000;
  }

  /**
   * Crea y timbra una factura via Facturapi.
   *
   * @param {object} invoiceData - Datos de la factura en formato Facturapi
   * @returns {Promise<{ok:boolean, uuid:string|null, xmlTimbrado:string|null, mensaje:string|null}>}
   */
  async timbrar(invoiceData) {
    const headers = {
      'Authorization': `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json',
    };

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeout);

    try {
      const res = await fetch(`${this.baseUrl}/invoices`, {
        method: 'POST',
        headers,
        body: JSON.stringify(invoiceData),
        signal: controller.signal,
      });

      const body = await res.json();

      if (!res.ok) {
        const msg = body.message || body.error || JSON.stringify(body);
        return { ok: false, uuid: null, xmlTimbrado: null, mensaje: `Facturapi HTTP ${res.status}: ${msg}` };
      }

      // La respuesta de Facturapi incluye: id, uuid, status, stamp, items, etc.
      // El XML timbrado se obtiene por separado con GET /invoices/{id}/xml
      const invoiceId = body.id;
      const uuid = body.uuid;
      let xmlTimbrado = null;

      // Intentar descargar el XML timbrado
      if (invoiceId) {
        try {
          const xmlRes = await fetch(`${this.baseUrl}/invoices/${invoiceId}/xml`, {
            headers: { 'Authorization': `Bearer ${this.apiKey}` },
            signal: AbortSignal.timeout(10000),
          });
          if (xmlRes.ok) {
            xmlTimbrado = await xmlRes.text();
          }
        } catch (_) { /* XML opcional */ }
      }

      return {
        ok: true,
        uuid,
        xmlTimbrado,
        fechaTimbrado: body.stamp?.date || body.date || new Date().toISOString(),
        mensaje: null,
        invoiceId,
        rawResponse: body,
      };
    } catch (e) {
      return {
        ok: false, uuid: null, xmlTimbrado: null,
        mensaje: `Facturapi error: ${e.message}`,
      };
    } finally {
      clearTimeout(timer);
    }
  }

  /** Cancela una factura por UUID */
  async cancelar(uuid) {
    const res = await fetch(`${this.baseUrl}/invoices/cancel`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ uuid }),
    });
    const body = await res.json();
    return { ok: res.ok, ...body };
  }
}

export { FacturapiConnector };

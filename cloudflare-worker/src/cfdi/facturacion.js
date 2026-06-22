// Servicio de facturacion via Facturapi.io
// Facturapi maneja XML, firma y timbrado internamente.
// Solo enviamos JSON con los datos del CFDI.

import { FacturapiConnector } from './facturapi.js';

/**
 * Timbra una factura via Facturapi.
 *
 * @param {{
 *   tenant: object,
 *   conceptos: Array,
 *   receptor: object,
 *   env: object,
 *   firestore: object | null,
 *   paymentId: string | null,
 * }} params
 */
async function timbrarFactura(params) {
  const { tenant, env, firestore, conceptos, receptor, paymentId } = params;
  const settings = tenant.settings;
  const now = new Date();

  const isGenerico = (receptor?.rfc || 'XAXX010101000') === 'XAXX010101000';

  const invoiceData = {
    type: 'I',
    payment_form: settings.forma_pago ?? '01',
    payment_method: settings.metodo_pago ?? 'PUE',
    use: receptor?.uso_cfdi ?? (isGenerico ? 'S01' : settings.uso_cfdi ?? 'G03'),
    currency: 'MXN',
    exchange: 1,
    series: settings.serie ?? 'F',
    folio_number: settings.folio_actual ?? 1,
    date: now.toISOString(),
    customer: {
      legal_name: receptor?.nombre ?? (isGenerico ? 'PUBLICO EN GENERAL' : 'CLIENTE'),
      tax_id: receptor?.rfc ?? (isGenerico ? 'XAXX010101000' : 'XEXX010101000'),
      tax_system: receptor?.regimen_fiscal ?? '616',
      email: receptor?.email || undefined,
      address: {
        street: receptor?.direccion || tenant.settings?.address || 'CONOCIDO',
        exterior: 'S/N',
        zip: receptor?.codigo_postal ?? settings.postal_code ?? '94720',
        country: 'MEX',
      },
    },
    items: (conceptos ?? []).map(c => ({
      quantity: c.cantidad ?? 1,
      product: {
        description: c.descripcion,
        product_key: c.claveProdServ,
        price: c.valorUnitario,
        tax_included: false,
      },
    })),
  };

  if (isGenerico) {
    invoiceData.global = {
      periodicity: 'month',
      months: String(now.getMonth() + 1).padStart(2, '0'),
      year: now.getFullYear(),
    };
  }

  const conector = new FacturapiConnector({
    baseUrl: env.FACTURAPI_BASE_URL,
    apiKey: env.FACTURAPI_API_KEY,
    timeout: parseInt(env.FACTURAPI_TIMEOUT ?? '30000', 10),
  });

  const resultado = await conector.timbrar(invoiceData);

  // Guardar en Firestore
  if (resultado.ok && firestore) {
    const total = invoiceData.items.reduce(
      (sum, i) => sum + (i.product.price * i.quantity), 0,
    );

    const invoiceDoc = {
      tenant_id: tenant.id,
      uuid: resultado.uuid,
      serie: invoiceData.series,
      folio: String(invoiceData.folio_number),
      fecha: now.toISOString(),
      fecha_timbrado: resultado.fechaTimbrado,
      emisor_rfc: settings.rfc ?? '',
      receptor_rfc: invoiceData.customer.tax_id,
      receptor_nombre: invoiceData.customer.legal_name,
      total,
      moneda: invoiceData.currency,
      tipo: invoiceData.type,
      xml_timbrado: resultado.xmlTimbrado,
      facturapi_invoice_id: resultado.invoiceId,
      payment_id: paymentId || null,
      status: 'vigente',
      created_at: now,
    };

    try {
      await firestore.fsSet(
        firestore.projectId,
        `tenants/${tenant.id}/facturas/${resultado.uuid}`,
        invoiceDoc,
        firestore.token,
      );
    } catch (e) {
      console.error('[facturacion] Error guardando factura:', e.message);
    }

    // Vincular al payment si existe
    if (paymentId) {
      try {
        await firestore.fsUpdate(
          firestore.projectId,
          `tenants/${tenant.id}/payments/${paymentId}`,
          { factura_uuid: resultado.uuid, facturado_at: now },
          firestore.token,
        );
      } catch (e) {
        console.error('[facturacion] Error vinculando payment:', e.message);
      }
    }

    // Incrementar folio
    if (settings.folio_actual != null) {
      try {
        await firestore.fsUpdate(
          firestore.projectId,
          `tenants/${tenant.id}`,
          { 'settings.folio_actual': settings.folio_actual + 1 },
          firestore.token,
        );
      } catch (e) {
        console.error('[facturacion] Error incrementando folio:', e.message);
      }
    }
  }

  return {
    ok: resultado.ok,
    uuid: resultado.uuid,
    xmlTimbrado: resultado.xmlTimbrado,
    fechaTimbrado: resultado.fechaTimbrado,
    mensaje: resultado.mensaje,
    invoiceId: resultado.invoiceId,
  };
}

export { timbrarFactura };

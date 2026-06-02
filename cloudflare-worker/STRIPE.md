# Facturación SaaS con Stripe (epic #36)

Cobro B2B: OmniGym le cobra a cada gimnasio (tenant) una suscripción mensual.
Todo el flujo vive en el worker; la app Flutter solo abre el link y muestra estado.

## Flujo
```
App → POST /billing/checkout {tenantId, priceId}  → worker crea Customer + Checkout
    → devuelve {url}  → la app abre la URL (Checkout hospedado de Stripe)
Stripe → POST /billing/webhook (firmado)
    → invoice.paid           → subscription_status=active, past_due=false,
                               billing_cycle_end = fin de periodo  + tenant_invoices
    → invoice.payment_failed → past_due=true
    → subscription.deleted   → subscription_status=cancelled
Gestionar/cancelar: POST /billing/portal {tenantId} → {url} del Customer Portal.
```

## Setup (una vez)

1. Crear cuenta Stripe (empezar en **modo test**).
2. Secrets en el worker:
   ```bash
   cd cloudflare-worker
   npx wrangler secret put STRIPE_SECRET_KEY        # sk_test_...
   npx wrangler secret put STRIPE_WEBHOOK_SECRET    # whsec_... (paso 4)
   ```
3. Crear los **Precios** (uno por paquete, recurrente mensual, MXN). De momento se
   pueden crear en el Dashboard y guardar el `price_id`; con #37 el CRUD del
   SuperAdmin los creará vía API automáticamente.
4. Registrar el **webhook** en Stripe Dashboard → Developers → Webhooks:
   - URL: `https://omni-gym.hadith024.workers.dev/billing/webhook`
   - Eventos: `invoice.paid`, `invoice.payment_failed`, `customer.subscription.deleted`
   - Copiar el `whsec_...` al secret del paso 2.
5. `npx wrangler deploy`

## Probar (modo test)
- Tarjeta de prueba: `4242 4242 4242 4242`, fecha futura, CVC cualquiera.
- Tras pagar, el webhook deja el tenant en `subscription_status=active` y empuja
  `billing_cycle_end`. El cron diario (#21) marca `past_due` si no se renueva.

## Datos en Firestore
- `tenants/{id}`: + `stripe_customer_id`, `stripe_subscription_id`, `package_price_id`
- `tenant_invoices/{stripe_invoice_id}`: historial de cobros
- `stripe_events/{event_id}`: idempotencia del webhook

# OmniGym

SaaS B2B para gestion integral de cadenas de gimnasios con cumplimiento SAT
(Mexico). Multi-tenant, white-label, facturacion recurrente con Stripe y
check-ins por QR.

## Arquitectura

```
App Flutter (Android, iOS, web)  -->  Firebase Auth / Firestore / Storage
                                           |
Cloudflare Worker (REST API)  <--->  Stripe (cobros SaaS B2B)
  +-- R2 (logos, fotos de perfil)
  +-- D1 (catalogo postal SEPOMEX)
  +-- Cron triggers (deudores, avisos de vencimiento)

Firebase Functions  -->  onUserWritten: sincroniza custom claims
```

## Stack

| Capa       | Tecnologia                                      |
|------------|-------------------------------------------------|
| App        | Flutter 3.x + Dart 3.x, Riverpod, GoRouter      |
| Modelos    | Freezed + json_serializable                     |
| Backend    | Cloudflare Workers (JS), Firebase Functions (TS)|
| Base datos | Firestore, Cloudflare D1 (catalogo SEPOMEX)     |
| Archivos   | Cloudflare R2                                   |
| Cobros     | Stripe (Checkout, Customer Portal, Webhooks)    |
| Email      | Resend (transaccionales con marca)              |
| Graficos   | fl_chart                                        |

## Estructura del proyecto

```
lib/
  app/          Router, tema, shell con sidebar/drawer
  core/         Modelos, providers, repositorios, servicios
  features/     Pantallas organizadas por dominio
    auth/         Login, registro, recuperacion de contrasena
    billing/      Pantalla de suscripcion + gate de cobro
    branches/     CRUD de sucursales con mini-mapas
    dashboard/    Owner dashboard + Manager dashboard
    members/      Socios: CRUD, QR, filtros, suspension/reactivacion
    memberships/  Planes (CRUD) + pagos (registro manual)
    profile/      Perfil del operador, foto, notificaciones
    reports/      Ingresos por periodo, graficas, desglose por plan
    scanner/      Control de acceso por QR + panel de check-ins
    settings/     Branding (logo, color primario)
    staff/        Invitacion y gestion de operadores (owner/staff)
    superadmin/   Consola multi-tenant, paquetes de suscripcion
cloudflare-worker/
  src/index.js   API REST (upload, billing, staff, members, catalogos)
  d1/            Esquema y seed del catalogo postal SEPOMEX
  wrangler.toml  Config R2 + D1 + cron triggers
functions/
  src/index.ts   Trigger onUserWritten + callable createStaffUser
test/            Tests unitarios y de widget
```

## Roles y permisos

| Rol         | Alcance                                              |
|-------------|------------------------------------------------------|
| superuser   | Consola multi-tenant, paquetes de suscripcion, SAT   |
| owner       | Su gimnasio: dashboard, sucursales, socios, staff    |
| staff       | Su sucursal: escaner QR, check-ins del dia           |
| member      | Socio: historial de check-ins (coleccion propia)     |

## Requisitos previos

- **Flutter SDK** `^3.11.5`
- **Node.js** `^20` (para Functions y Wrangler)
- **Firebase CLI** (`npm i -g firebase-tools`)
- **Cloudflare Wrangler** (`npx wrangler`)
- **Cuenta Stripe** (empezar en modo test)
- **Cuenta Resend** (emails transaccionales)
- **Cuenta Google Cloud** con service account (para el worker)

---

## Setup paso a paso

### 1. Firebase

```bash
# Instalar CLI y hacer login
npm i -g firebase-tools
firebase login

# Configurar proyecto Flutter con Firebase
dart pub global activate flutterfire_cli
flutterfire configure --project=omnigym-567a8
```

#### Firestore

```bash
# Desplegar reglas e indices
firebase deploy --only firestore:rules,firestore:indexes
```

#### Storage

```bash
firebase deploy --only storage:rules
```

#### Functions

La funcion `onUserWritten` sincroniza custom claims cada vez que se escribe
un documento en `/users/{uid}`. Sin esto, los operadores no reciben sus
permisos en el JWT.

```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions
```

#### Crear superusuario

```bash
cd functions
GOOGLE_APPLICATION_CREDENTIALS=/ruta/al/service-account.json \
  node create-superuser.js
```

Esto crea `super@omnigym.mx` (cambia las credenciales en el script antes de
correrlo).

### 2. Cloudflare Worker

El worker expone la API REST que consume la app Flutter: subida de archivos
a R2, Stripe (checkout/portal/webhooks), creacion de staff y socios, y el
catalogo postal SEPOMEX.

#### R2

Crear el bucket desde el dashboard de Cloudflare con nombre `omni-gym`.

#### D1 (catalogo postal SEPOMEX)

```bash
cd cloudflare-worker

# Crear base de datos
npx wrangler d1 create omnigym_catalogs

# Copiar el database_id que imprime a wrangler.toml

# Crear esquema
npx wrangler d1 execute omnigym_catalogs --file=./d1/schema.sql --remote

# Generar y cargar datos (~145k registros)
node d1/import_sepomex.mjs
npx wrangler d1 execute omnigym_catalogs --file=./d1/seed.sql --remote
```

#### Secrets del worker

```bash
cd cloudflare-worker

npx wrangler secret put STRIPE_SECRET_KEY        # sk_test_...
npx wrangler secret put STRIPE_WEBHOOK_SECRET    # whsec_...
npx wrangler secret put SA_JSON                   # JSON de la service account de Firebase
npx wrangler secret put RESEND_API_KEY            # re_...
npx wrangler secret put FIREBASE_API_KEY          # Web API key de Firebase (para envio de emails)
npx wrangler secret put UPLOAD_SECRET             # Token Bearer compartido con la app
npx wrangler secret put EMAIL_FROM                # "OmniGym <noreply@omni-gym.com>"
npx wrangler secret put TRIAL_DAYS               # Dias de prueba gratis (default 14)
```

#### Stripe

Configurar productos y precios (modo suscripcion mensual, MXN) en el
dashboard de Stripe. Luego registrar el webhook:

- URL: `https://<TU_WORKER>.<TU_SUBDOMINIO>.workers.dev/billing/webhook`
- Eventos:
  - `invoice.paid`
  - `invoice.payment_failed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`

Para mas detalle: `cloudflare-worker/STRIPE.md`

#### Desplegar

```bash
npx wrangler deploy
```

### 3. App Flutter

```bash
# Instalar dependencias
flutter pub get

# Regenerar modelos Freezed (solo si modificaste los .dart fuente)
dart run build_runner build --delete-conflicting-outputs

# Correr en modo debug
flutter run --dart-define=R2_UPLOAD_SECRET=tu-secret-local

# Build release
flutter build apk --dart-define=R2_UPLOAD_SECRET=tu-secret-prod
flutter build web --dart-define=R2_UPLOAD_SECRET=tu-secret-prod
```

El `--dart-define=R2_UPLOAD_SECRET=...` es requerido: el worker exige un
Bearer token compartido en cada request. Para desarrollo local usa
`omni-r2-2025-dev` (valor por defecto en `WorkerService` y `R2StorageService`).

---

## Variables de entorno

### Cloudflare Worker

| Variable              | Descripcion                                      |
|-----------------------|--------------------------------------------------|
| `STRIPE_SECRET_KEY`   | Clave secreta de Stripe (test/live)              |
| `STRIPE_WEBHOOK_SECRET`| Firma del webhook de Stripe (`whsec_...`)       |
| `SA_JSON`             | JSON de la service account de Firebase Admin     |
| `RESEND_API_KEY`      | API key de Resend para emails con marca          |
| `FIREBASE_API_KEY`    | Web API key de Firebase para envio de emails     |
| `UPLOAD_SECRET`       | Token Bearer compartido con la app               |
| `EMAIL_FROM`          | Direccion remitente de emails                    |
| `TRIAL_DAYS`          | Dias de prueba gratis (default `14`)             |

### Flutter (compile-time)

| Variable            | Descripcion                     | Default              |
|---------------------|---------------------------------|----------------------|
| `R2_UPLOAD_SECRET`  | Token Bearer para el worker     | `omni-r2-2025-dev`   |

---

## Comandos utiles

```bash
# Analisis estatico
flutter analyze

# Tests de la app Flutter
flutter test

# Tests de Firebase Functions
cd functions && npm test

# Regenerar modelos Freezed/JSON
dart run build_runner build --delete-conflicting-outputs

# Desplegar Firestore (reglas + indices)
firebase deploy --only firestore

# Desplegar Firebase Functions
firebase deploy --only functions

# Desplegar Cloudflare Worker
npx wrangler deploy -c cloudflare-worker/wrangler.toml

# Seed del catalogo SEPOMEX
cd cloudflare-worker
node d1/import_sepomex.mjs
npx wrangler d1 execute omnigym_catalogs --file=./d1/seed.sql --remote
```

---

## Flujos principales

1. **Registro de gimnasio** — El owner crea su tenant y su cuenta desde
   `/register`. La app lo guia a iniciar su prueba gratis (14 dias con
   tarjeta, sin cobro inmediato).

2. **Alta de socios** — El owner/staff crea socios con correo, vencimiento
   y sucursales permitidas. El worker genera una contrasena temporal y un
   QR token unico. El socio recibe un email con sus credenciales.

3. **Check-in** — Escaner QR (camara en mobile, lector USB en desktop) o
   modo kiosko (pantalla completa, disenado para tablets en recepcion).
   Valida suscripcion del gym, membresia activa y sucursal permitida.

4. **Cobro SaaS** — Al terminar la prueba, Stripe cobra automaticamente.
   El webhook actualiza Firestore (`subscription_status`, `billing_cycle_end`).
   Si el pago falla, el worker notifica al owner y activa el kill switch
   (bloquea check-ins y altas de socios hasta regularizar).

5. **Consola SuperAdmin** — Gestion multi-tenant, paquetes de suscripcion
   (CRUD con sincronizacion a Stripe), ejecucion de crons.

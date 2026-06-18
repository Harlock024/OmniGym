/**
 * Demo seed script para OmniGym.
 *
 * Crea datos de demo contra los emuladores locales de Firebase.
 * No requiere Cloudflare Worker ni Stripe — solo Firebase emulators.
 *
 * Uso:
 *   1. firebase emulators:start
 *   2. node scripts/demo-seed.js
 *
 * Crea: 1 superuser, 1 gym (owner), 1 sucursal, 1 staff,
 *        5 socios con QR tokens, 2 planes de membresia.
 */

const admin = require('firebase-admin');

// ── Conectar a emuladores ────────────────────────────────────────────────────
process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = 'localhost:9199';

const app = admin.initializeApp({
  projectId: 'omnigym-567a8',
});
const auth = admin.auth();
const db = admin.firestore();

// ── Helpers ──────────────────────────────────────────────────────────────────

function generateQrToken() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let token = 'QR';
  for (let i = 0; i < 20; i++) token += chars[Math.floor(Math.random() * chars.length)];
  return token;
}

async function createAuthUser(email, password, displayName) {
  try {
    return await auth.createUser({ email, password, displayName });
  } catch (e) {
    if (e.code === 'auth/email-already-exists') {
      return await auth.getUserByEmail(email);
    }
    throw e;
  }
}

async function setClaims(uid, claims) {
  await auth.setCustomUserClaims(uid, claims);
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('🌱 Creando datos de demo para OmniGym...\n');

  const tenantId = 'demo-gym-01';
  const branchId = 'demo-branch-01';
  const gymName = 'IronFit Centro';

  // ── 1. Superusuario ────────────────────────────────────────────────────
  console.log('1/6  Superusuario...');
  const superUser = await createAuthUser('super@demo.mx', 'Demo1234!', 'Super Admin');
  await setClaims(superUser.uid, { role: 'superuser' });
  await db.collection('users').doc(superUser.uid).set({
    name: 'Super Admin',
    email: 'super@demo.mx',
    role: 'superuser',
    status: 'active',
    tenant_id: null,
    branch_id: null,
    notification_prefs: { check_ins: true, payments: true, member_expiry: true, marketing: false },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('   ✓ super@demo.mx / Demo1234!');

  // ── 2. Owner + Tenant ──────────────────────────────────────────────────
  console.log('2/6  Owner + Tenant...');
  const owner = await createAuthUser('owner@demo.mx', 'Demo1234!', 'Carlos Admin');
  await setClaims(owner.uid, { role: 'owner', tenant_id: tenantId });
  await db.collection('users').doc(owner.uid).set({
    name: 'Carlos Admin',
    email: 'owner@demo.mx',
    role: 'owner',
    status: 'active',
    tenant_id: tenantId,
    branch_id: null,
    notification_prefs: { check_ins: true, payments: true, member_expiry: true, marketing: false },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  await db.collection('tenants').doc(tenantId).set({
    name: gymName,
    slug: 'ironfit-centro',
    subscription_status: 'active',
    billing_cycle_end: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 86400000)),
    past_due: false,
    package_price_id: 'price_demo',
    stripe_subscription_status: 'active',
    settings: { primary_color: '#2563EB' },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('   ✓ owner@demo.mx / Demo1234!');

  // ── 3. Sucursal ────────────────────────────────────────────────────────
  console.log('3/6  Sucursal...');
  await db.collection('tenants').doc(tenantId).collection('branches').doc(branchId).set({
    name: 'IronFit Sucursal Centro',
    is_active: true,
    address: { street: 'Av. Reforma 123', city: 'CDMX', state: 'CDMX', postal_code: '06600' },
    location: { latitude: 19.4326, longitude: -99.1332 },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('   ✓ IronFit Centro');

  // ── 4. Staff ───────────────────────────────────────────────────────────
  console.log('4/6  Staff...');
  const staff = await createAuthUser('staff@demo.mx', 'Demo1234!', 'Ana Recepcion');
  await setClaims(staff.uid, { role: 'staff', tenant_id: tenantId, branch_id: branchId });
  await db.collection('users').doc(staff.uid).set({
    name: 'Ana Recepcion',
    email: 'staff@demo.mx',
    role: 'staff',
    status: 'active',
    tenant_id: tenantId,
    branch_id: branchId,
    notification_prefs: { check_ins: true, payments: false, member_expiry: true, marketing: false },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('   ✓ staff@demo.mx / Demo1234!');

  // ── 5. Planes de membresia ─────────────────────────────────────────────
  console.log('5/6  Planes de membresia...');
  const planMensual = {
    name: 'Plan Mensual',
    price: 499,
    duration_days: 30,
    is_active: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  const planAnual = {
    name: 'Plan Anual',
    price: 3999,
    duration_days: 365,
    is_active: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  await db.collection('tenants').doc(tenantId).collection('membership_plans').doc('plan-mensual').set(planMensual);
  await db.collection('tenants').doc(tenantId).collection('membership_plans').doc('plan-anual').set(planAnual);
  console.log('   ✓ Plan Mensual ($499) + Plan Anual ($3999)');

  // ── 6. Socios ──────────────────────────────────────────────────────────
  console.log('6/6  Socios...');
  const miembros = [
    { name: 'Laura Martinez', email: 'socio1@demo.mx', expDays: 30 },
    { name: 'Miguel Torres',  email: 'socio2@demo.mx', expDays: 15 },
    { name: 'Sofia Herrera',  email: 'socio3@demo.mx', expDays:  5 },
    { name: 'Daniel Rojas',   email: 'socio4@demo.mx', expDays: 90 },
    { name: 'Valeria Lopez',  email: 'socio5@demo.mx', expDays: -1 }, // vencido
  ];

  for (const m of miembros) {
    const memberUser = await createAuthUser(m.email, 'Demo1234!', m.name);
    const qrToken = generateQrToken();
    const expDate = new Date(Date.now() + m.expDays * 86400000);

    await setClaims(memberUser.uid, { role: 'member', tenant_id: tenantId });
    await db.collection('tenants').doc(tenantId).collection('members').doc(memberUser.uid).set({
      uid: memberUser.uid,
      tenant_id: tenantId,
      name: m.name,
      email: m.email,
      qr_token: qrToken,
      expiration_date: admin.firestore.Timestamp.fromDate(expDate),
      allowed_branches: [branchId],
      access_status: m.expDays < 0 ? 'suspended' : 'active',
      plan_id: 'plan-mensual',
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Generar algunos check-ins para los socios activos
    if (m.expDays >= 0) {
      const checkInsCount = Math.floor(Math.random() * 5) + 1;
      for (let d = 0; d < checkInsCount; d++) {
        const ts = new Date(Date.now() - d * 86400000 - Math.random() * 43200000);
        await db.collection('tenants').doc(tenantId)
          .collection('branches').doc(branchId)
          .collection('check_ins').doc().set({
            member_id: memberUser.uid,
            member_name: m.name,
            qr_token: qrToken,
            tenant_id: tenantId,
            branch_id: branchId,
            expiration_date: admin.firestore.Timestamp.fromDate(expDate),
            plan_id: 'plan-mensual',
            timestamp: admin.firestore.Timestamp.fromDate(ts),
          });
      }
    }
  }
  console.log('   ✓ 5 socios (socio1-5@demo.mx / Demo1234!)');

  // ── Resumen ────────────────────────────────────────────────────────────
  console.log('\n══════════════════════════════════════════');
  console.log('  Demo lista. Credenciales:');
  console.log('══════════════════════════════════════════');
  console.log('  SuperAdmin:  super@demo.mx  / Demo1234!');
  console.log('  Owner:       owner@demo.mx  / Demo1234!');
  console.log('  Staff:       staff@demo.mx  / Demo1234!');
  console.log('  Socio:       socio1@demo.mx / Demo1234!');
  console.log('               socio2@demo.mx / Demo1234!');
  console.log('               socio3@demo.mx / Demo1234!');
  console.log('               socio4@demo.mx / Demo1234!');
  console.log('               socio5@demo.mx / Demo1234! (vencido)');
  console.log('══════════════════════════════════════════\n');

  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Error:', e.message);
  process.exit(1);
});

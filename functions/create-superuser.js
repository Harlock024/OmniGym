/**
 * Script de uso único para crear el superusuario de OmniGym.
 * Uso: node functions/create-superuser.js
 */

const admin = require('firebase-admin');

// Ajusta estos valores antes de correr
const SUPERUSER_EMAIL = 'super@omnigym.mx';
const SUPERUSER_PASSWORD = 'CambiaEsto123!';
const SUPERUSER_NAME = 'Super Admin';

admin.initializeApp();

async function main() {
  const db = admin.firestore();
  const auth = admin.auth();

  // 1. Crear usuario en Firebase Auth (o reusar si ya existe)
  let uid;
  try {
    const existing = await auth.getUserByEmail(SUPERUSER_EMAIL);
    uid = existing.uid;
    console.log(`Usuario ya existe: ${uid}`);
  } catch {
    const created = await auth.createUser({
      email: SUPERUSER_EMAIL,
      password: SUPERUSER_PASSWORD,
      displayName: SUPERUSER_NAME,
    });
    uid = created.uid;
    console.log(`Usuario creado: ${uid}`);
  }

  // 2. Crear/actualizar doc en Firestore /users/{uid}
  await db.collection('users').doc(uid).set({
    name: SUPERUSER_NAME,
    email: SUPERUSER_EMAIL,
    role: 'superuser',
    status: 'active',
    tenant_id: null,
    branch_id: null,
    notification_prefs: {
      check_ins: true,
      payments: true,
      member_expiry: true,
      marketing: false,
    },
    permissions: {},
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log(`✅ Superusuario listo: ${SUPERUSER_EMAIL}`);
  process.exit(0);
}

main().catch((e) => {
  console.error('❌ Error:', e.message);
  process.exit(1);
});

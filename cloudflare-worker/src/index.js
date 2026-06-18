const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

// ── Helpers ──────────────────────────────────────────────────────────────────

function jsonRes(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function checkAuth(request, env) {
  return (request.headers.get('Authorization') ?? '') === `Bearer ${env.UPLOAD_SECRET}`;
}

// ── Google / Firebase Admin auth ──────────────────────────────────────────────

function b64url(str) {
  return btoa(str).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function bufToB64url(buf) {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function pemToBytes(pem) {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getAdminToken(env) {
  const sa = JSON.parse(env.SA_JSON);
  const saEmail      = sa.client_email;
  const saPrivateKey = sa.private_key;

  const now = Math.floor(Date.now() / 1000);
  const header  = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    iss: saEmail,
    scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));

  const sigInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(saPrivateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(sigInput));
  const jwt = `${sigInput}.${bufToB64url(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) throw new Error('Token error: ' + JSON.stringify(data));
  return data.access_token;
}

// ── Firebase Auth helpers ─────────────────────────────────────────────────────

async function fbAuthPost(path, body, token) {
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Firebase Auth ${path} error: ${JSON.stringify(data?.error ?? data)}`);
  return data;
}

async function createAuthUser(email, displayName, token) {
  const data = await fbAuthPost('signUp', {
    email,
    displayName,
    emailVerified: false,
    disabled: false,
  }, token);
  return data.localId;
}

// Crea un usuario en Auth con contraseña usando el endpoint admin del proyecto
async function createMemberAuth(projectId, email, displayName, password, token) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password, displayName, emailVerified: false, disabled: false }),
    },
  );
  const data = await res.json();
  if (!res.ok) throw new Error(`CreateMemberAuth error: ${JSON.stringify(data?.error ?? data)}`);
  return data.localId; // UID
}

async function setCustomClaims(uid, claims, token) {
  await fbAuthPost('update', {
    localId: uid,
    customAttributes: JSON.stringify(claims),
  }, token);
}

async function deleteAuthUser(uid, token) {
  await fbAuthPost('delete', { localId: uid }, token);
}

// IMPORTANTE: el correo SOLO se envía si la llamada se hace con la Web API key
// como petición de cliente (sin token admin). Con token admin, sendOobCode solo
// devuelve el oobLink y NO manda email.
async function sendPasswordReset(email, env) {
  const apiKey = env.FIREBASE_API_KEY ?? 'AIzaSyCVRVQqgDDg9xK_ZU-i4BrkGnH7k7tNl0U';
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ requestType: 'PASSWORD_RESET', email }),
    },
  );
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`sendPasswordReset error: ${JSON.stringify(data?.error ?? data)}`);
  }
  return data;
}

// Genera el enlace para establecer contraseña SIN enviar el email de Firebase.
// Con token admin y returnOobLink:true, sendOobCode devuelve el oobLink y no
// manda nada — así lo enviamos nosotros con Resend (plantilla con marca).
async function generatePasswordResetLink(email, token) {
  const data = await fbAuthPost('sendOobCode', {
    requestType: 'PASSWORD_RESET',
    email,
    returnOobLink: true,
  }, token);
  return data.oobLink;
}

// ── Firestore REST helpers ────────────────────────────────────────────────────

function toFsVal(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toFsVal) } };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, val] of Object.entries(v)) {
      if (val !== undefined) fields[k] = toFsVal(val);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(v) };
}

// Crea o sobreescribe un documento en Firestore via REST (PATCH)
async function fsSet(projectId, docPath, data, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}`;
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    if (v !== undefined) fields[k] = toFsVal(v);
  }
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const err = await res.json();
    throw new Error(`Firestore set error: ${JSON.stringify(err?.error ?? err)}`);
  }
  return res.json();
}

// Elimina un documento en Firestore via REST (DELETE)
async function fsDelete(projectId, docPath, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${token}` },
  });
  if (!res.ok && res.status !== 404) {
    const err = await res.json();
    throw new Error(`Firestore delete error: ${JSON.stringify(err?.error ?? err)}`);
  }
}

// Actualiza (merge) campos de un documento usando updateMask para NO sobrescribir
// el resto del documento. Imprescindible para los crons que marcan banderas.
async function fsUpdate(projectId, docPath, data, token) {
  const params = Object.keys(data)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&');
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}?${params}`;
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    if (v !== undefined) fields[k] = toFsVal(v);
  }
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const err = await res.json();
    throw new Error(`Firestore update error: ${JSON.stringify(err?.error ?? err)}`);
  }
  return res.json();
}

// ── Firestore REST: lectura ─────────────────────────────────────────────────

// Convierte un valor REST de Firestore a JS (inverso de toFsVal).
function fromFsVal(v) {
  if (v == null || 'nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return parseInt(v.integerValue, 10);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('referenceValue' in v) return v.referenceValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(fromFsVal);
  if ('mapValue' in v) {
    const out = {};
    for (const [k, val] of Object.entries(v.mapValue.fields ?? {})) out[k] = fromFsVal(val);
    return out;
  }
  return null;
}

// Aplana un documento REST a { id, path, ...campos }.
function fsParseDoc(doc) {
  const fields = {};
  for (const [k, v] of Object.entries(doc.fields ?? {})) fields[k] = fromFsVal(v);
  const marker = '/documents/';
  const path = doc.name.substring(doc.name.indexOf(marker) + marker.length);
  return { id: path.split('/').pop(), path, ...fields };
}

// Ejecuta una structuredQuery (soporta collectionGroup con allDescendants).
async function fsRunQuery(projectId, structuredQuery, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ structuredQuery }),
  });
  if (!res.ok) {
    const err = await res.json();
    throw new Error(`Firestore runQuery error: ${JSON.stringify(err?.error ?? err)}`);
  }
  const rows = await res.json();
  return rows.filter((r) => r.document).map((r) => fsParseDoc(r.document));
}

// Atajos para construir filtros de structuredQuery.
const fEq = (field, value) => ({
  fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value },
});
const fCmp = (field, op, value) => ({
  fieldFilter: { field: { fieldPath: field }, op, value },
});
const fAnd = (...filters) => ({ compositeFilter: { op: 'AND', filters } });

// ── Generadores ───────────────────────────────────────────────────────────────

function generateTempPassword() {
  const upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower  = 'abcdefghjkmnpqrstuvwxyz';
  const digits = '23456789';
  const all    = upper + lower + digits;
  // Al menos una mayúscula y un dígito garantizados
  let pw = upper[Math.floor(Math.random() * upper.length)]
         + digits[Math.floor(Math.random() * digits.length)];
  for (let i = 0; i < 6; i++) pw += all[Math.floor(Math.random() * all.length)];
  return pw.split('').sort(() => Math.random() - 0.5).join('');
}

function generateQrToken() {
  const arr = new Uint8Array(12);
  crypto.getRandomValues(arr);
  return 'QR' + Array.from(arr, b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
}

// ── Email de bienvenida (Resend) ──────────────────────────────────────────────

// Devuelve true si el email se envió correctamente, false si falló.
async function sendWelcomeEmail(to, memberName, tempPassword, gymName, env) {
  if (!env.RESEND_API_KEY) {
    return false;
  }
  const from = env.EMAIL_FROM ?? `OmniGym <noreply@omni-gym.com>`;
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: `Bienvenido a ${gymName} 🏋️`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:32px;background:#0f0f0f;color:#fff;border-radius:16px;">
          <h2 style="color:#3B82F6;margin:0 0 8px;">¡Bienvenido, ${memberName}!</h2>
          <p style="color:#aaa;margin:0 0 24px;">Tu cuenta de socio ha sido creada en <strong style="color:#fff;">${gymName}</strong>.</p>
          <div style="background:#1a1a1a;padding:20px 24px;border-radius:10px;border:1px solid #333;margin-bottom:24px;">
            <p style="margin:6px 0;color:#888;">Correo electrónico:</p>
            <p style="margin:0 0 14px;font-size:1em;font-weight:bold;">${to}</p>
            <p style="margin:6px 0;color:#888;">Contraseña temporal:</p>
            <p style="margin:0;font-size:1.6em;font-weight:bold;letter-spacing:4px;color:#3B82F6;font-family:monospace;">${tempPassword}</p>
          </div>
          <p style="color:#555;font-size:0.82em;margin:0;">Por seguridad, te recomendamos cambiar tu contraseña al iniciar sesión por primera vez.</p>
        </div>
      `,
    }),
  });
  if (!res.ok) {
    console.error('[sendWelcomeEmail] Resend error:', await res.text());
    return false;
  }
  return true;
}

// Email de invitación a un operador (staff/owner) con marca, vía Resend.
// Lleva un botón al enlace de set-password (oobLink). Devuelve true si se envió.
async function sendStaffInviteEmail(to, name, gymName, roleLabel, link, env) {
  if (!env.RESEND_API_KEY) {
    return false;
  }
  const from = env.EMAIL_FROM ?? `OmniGym <noreply@omni-gym.com>`;
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: `Te invitaron a ${gymName} 🏋️`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:32px;background:#0f0f0f;color:#fff;border-radius:16px;">
          <h2 style="color:#3B82F6;margin:0 0 8px;">¡Hola, ${name}!</h2>
          <p style="color:#aaa;margin:0 0 24px;">Te invitaron a unirte a <strong style="color:#fff;">${gymName}</strong> como <strong style="color:#fff;">${roleLabel}</strong>. Para activar tu cuenta, establece tu contraseña:</p>
          <div style="text-align:center;margin:0 0 24px;">
            <a href="${link}" style="display:inline-block;background:#3B82F6;color:#fff;text-decoration:none;font-weight:bold;padding:14px 28px;border-radius:10px;font-size:1em;">Establecer contraseña</a>
          </div>
          <div style="background:#1a1a1a;padding:16px 20px;border-radius:10px;border:1px solid #333;margin-bottom:24px;">
            <p style="margin:6px 0;color:#888;">Correo de acceso:</p>
            <p style="margin:0;font-size:1em;font-weight:bold;">${to}</p>
          </div>
          <p style="color:#555;font-size:0.82em;margin:0;">Si el botón no funciona, copia este enlace en tu navegador:<br><span style="color:#777;word-break:break-all;">${link}</span></p>
        </div>
      `,
    }),
  });
  if (!res.ok) {
    console.error('[sendStaffInviteEmail] Resend error:', await res.text());
    return false;
  }
  return true;
}

// ── Main handler ──────────────────────────────────────────────────────────────

// ── Cron Triggers: automatización (sin Firebase Blaze) ──────────────────────
// Cloudflare ejecuta crons en UTC. México es UTC-6 todo el año.

const DAY_MS = 24 * 60 * 60 * 1000;
const esc = (s) =>
  String(s ?? '').replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Lee un documento por path; null si no existe.
async function fsGet(projectId, docPath, token) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${docPath}`;
  const res = await fetch(url, { headers: { 'Authorization': `Bearer ${token}` } });
  if (res.status === 404) return null;
  if (!res.ok) {
    const err = await res.json();
    throw new Error(`Firestore get error: ${JSON.stringify(err?.error ?? err)}`);
  }
  return fsParseDoc(await res.json());
}

// Envío genérico de correo vía Resend. Devuelve true si se envió.
async function sendEmail(to, subject, html, env) {
  if (!env.RESEND_API_KEY) return false;
  const from = env.EMAIL_FROM ?? 'OmniGym <noreply@omni-gym.com>';
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to: [to], subject, html }),
  });
  if (!res.ok) {
    console.error('[sendEmail] Resend error:', await res.text());
    return false;
  }
  return true;
}

function expiryReminderHtml(memberName, gymName, daysLeft) {
  const cuando = daysLeft <= 0
    ? 'hoy'
    : (daysLeft === 1 ? 'mañana' : `en ${daysLeft} días`);
  return `
    <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:32px;background:#0f0f0f;color:#fff;border-radius:16px;">
      <h2 style="color:#3B82F6;margin:0 0 8px;">Hola, ${esc(memberName)}</h2>
      <p style="color:#aaa;margin:0 0 24px;">Tu membresía en <strong style="color:#fff;">${esc(gymName)}</strong> vence <strong style="color:#fff;">${cuando}</strong>.</p>
      <p style="color:#aaa;margin:0 0 24px;">Renueva a tiempo para no perder el acceso al gimnasio.</p>
      <p style="color:#555;font-size:0.82em;margin:0;">Si ya renovaste, ignora este mensaje.</p>
    </div>`;
}

function ownerSummaryHtml(ownerName, gymName, members) {
  const items = members
    .slice(0, 25)
    .map((m) => `<li style="margin:4px 0;">${esc(m.name)} — venció el ${new Date(m.expiration_date).toLocaleDateString('es-MX')}</li>`)
    .join('');
  const extra = members.length > 25 ? `<p style="color:#888;">…y ${members.length - 25} más.</p>` : '';
  return `
    <div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:32px;background:#0f0f0f;color:#fff;border-radius:16px;">
      <h2 style="color:#3B82F6;margin:0 0 8px;">Resumen semanal — ${esc(gymName)}</h2>
      <p style="color:#aaa;margin:0 0 16px;">Hola ${esc(ownerName)}, tienes <strong style="color:#fff;">${members.length}</strong> socio(s) vencido(s) sin renovar en los últimos 30 días:</p>
      <ul style="color:#ddd;padding-left:20px;margin:0 0 16px;">${items}</ul>
      ${extra}
      <p style="color:#555;font-size:0.82em;margin:0;">Reporte automático de OmniGym.</p>
    </div>`;
}

// Aviso al Owner cuando Stripe rechaza el cobro de su suscripción SaaS.
function paymentFailedHtml(ownerName, gymName) {
  return `
    <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:32px;background:#0f0f0f;color:#fff;border-radius:16px;">
      <h2 style="color:#EF4444;margin:0 0 8px;">Pago rechazado</h2>
      <p style="color:#aaa;margin:0 0 16px;">Hola ${esc(ownerName)}, no pudimos cobrar la suscripción de <strong style="color:#fff;">${esc(gymName)}</strong>.</p>
      <p style="color:#aaa;margin:0 0 24px;">Actualiza tu método de pago desde <strong style="color:#fff;">Mi suscripción</strong> para reactivar el servicio. Mientras el pago siga pendiente, el acceso al sistema queda suspendido.</p>
      <p style="color:#555;font-size:0.82em;margin:0;">Si ya lo resolviste, ignora este mensaje.</p>
    </div>`;
}

// Recordatorio al Owner de que su suscripción se renueva (cobra) pronto.
function renewalReminderHtml(ownerName, gymName, fecha) {
  return `
    <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:32px;background:#0f0f0f;color:#fff;border-radius:16px;">
      <h2 style="color:#3B82F6;margin:0 0 8px;">Tu suscripción se renueva pronto</h2>
      <p style="color:#aaa;margin:0 0 16px;">Hola ${esc(ownerName)}, la suscripción de <strong style="color:#fff;">${esc(gymName)}</strong> se renovará el <strong style="color:#fff;">${esc(fecha)}</strong>.</p>
      <p style="color:#aaa;margin:0 0 24px;">El cobro es automático con tu método de pago registrado. No necesitas hacer nada si todo está en orden.</p>
      <p style="color:#555;font-size:0.82em;margin:0;">Reporte automático de OmniGym.</p>
    </div>`;
}

// Owners activos de un tenant (con email), para notificaciones de cobro.
async function tenantOwners(projectId, tenantId, token) {
  const users = await fsRunQuery(projectId, {
    from: [{ collectionId: 'users' }],
    where: fEq('tenant_id', { stringValue: tenantId }),
  }, token);
  return users.filter((u) => u.role === 'owner' && u.status !== 'suspended' && u.email);
}

// Registra cada ejecución de cron para auditoría del SuperAdmin.
async function logCronRun(projectId, token, log) {
  const id = `${log.job}_${Date.now()}`;
  try {
    await fsSet(projectId, `cron_runs/${id}`, { ...log, ran_at: new Date(log.ran_at) }, token);
  } catch (e) {
    console.error('[logCronRun] no se pudo registrar la ejecución:', e.message);
  }
}

// Job diario: marca como deudores a los socios vencidos y aún activos.
async function runMarkDebtors(projectId, token) {
  const started = Date.now();
  const now = new Date();
  let scanned = 0, updated = 0; const errors = [];
  try {
    const members = await fsRunQuery(projectId, {
      from: [{ collectionId: 'members', allDescendants: true }],
      where: fAnd(
        fEq('access_status', { stringValue: 'active' }),
        fCmp('expiration_date', 'LESS_THAN', { timestampValue: now.toISOString() }),
      ),
    }, token);
    scanned = members.length;
    for (const m of members) {
      if (m.is_debtor === true) continue; // idempotente
      try {
        await fsUpdate(projectId, m.path, { is_debtor: true, debtor_since: now }, token);
        updated++;
      } catch (e) { errors.push(`${m.path}: ${e.message}`); }
    }
  } catch (e) { errors.push(e.message); }
  await logCronRun(projectId, token, {
    job: 'mark_debtors', ran_at: now, duration_ms: Date.now() - started,
    scanned, updated, emails_sent: 0, ok: errors.length === 0, errors,
  });
}

// Job diario: marca tenants con ciclo de facturación vencido como past_due.
async function runMarkPastDueTenants(projectId, token) {
  const started = Date.now();
  const now = new Date();
  let scanned = 0, updated = 0; const errors = [];
  try {
    const tenants = await fsRunQuery(projectId, {
      from: [{ collectionId: 'tenants' }],
      where: fAnd(
        fEq('subscription_status', { stringValue: 'active' }),
        fCmp('billing_cycle_end', 'LESS_THAN', { timestampValue: now.toISOString() }),
      ),
    }, token);
    scanned = tenants.length;
    for (const t of tenants) {
      if (t.past_due === true) continue;
      // Stripe es la fuente de verdad del cobro: solo es red de seguridad para
      // gyms con suscripción real (no para los que aún no inician su prueba).
      if (!t.stripe_customer_id) continue;
      try {
        await fsUpdate(projectId, t.path, { past_due: true, past_due_since: now }, token);
        updated++;
      } catch (e) { errors.push(`${t.path}: ${e.message}`); }
    }
  } catch (e) { errors.push(e.message); }
  await logCronRun(projectId, token, {
    job: 'mark_past_due_tenants', ran_at: now, duration_ms: Date.now() - started,
    scanned, updated, emails_sent: 0, ok: errors.length === 0, errors,
  });
}

// Job semanal: avisa a socios cuya membresía vence en los próximos 7 días.
async function runNotifyExpiringMembers(projectId, token, env) {
  const started = Date.now();
  const now = new Date();
  const in7 = new Date(now.getTime() + 7 * DAY_MS);
  let scanned = 0, emailsSent = 0; const errors = [];
  const gymNameCache = {};
  try {
    const members = await fsRunQuery(projectId, {
      from: [{ collectionId: 'members', allDescendants: true }],
      where: fAnd(
        fEq('access_status', { stringValue: 'active' }),
        fCmp('expiration_date', 'GREATER_THAN_OR_EQUAL', { timestampValue: now.toISOString() }),
        fCmp('expiration_date', 'LESS_THAN_OR_EQUAL', { timestampValue: in7.toISOString() }),
      ),
    }, token);
    scanned = members.length;
    for (const m of members) {
      if (!m.email) continue;
      const tenantId = m.tenant_id;
      if (tenantId && gymNameCache[tenantId] === undefined) {
        const t = await fsGet(projectId, `tenants/${tenantId}`, token);
        gymNameCache[tenantId] = t?.name ?? 'tu gimnasio';
      }
      const daysLeft = Math.ceil((new Date(m.expiration_date).getTime() - now.getTime()) / DAY_MS);
      try {
        const ok = await sendEmail(
          m.email,
          'Tu membresía vence pronto',
          expiryReminderHtml(m.name, gymNameCache[tenantId] ?? 'tu gimnasio', daysLeft),
          env,
        );
        if (ok) emailsSent++;
      } catch (e) { errors.push(`${m.email}: ${e.message}`); }
    }
  } catch (e) { errors.push(e.message); }
  await logCronRun(projectId, token, {
    job: 'notify_expiring_members', ran_at: now, duration_ms: Date.now() - started,
    scanned, updated: 0, emails_sent: emailsSent, ok: errors.length === 0, errors,
  });
}

// Job semanal: envía a cada Owner un resumen de socios vencidos (últimos 30 días).
async function runNotifyOwnersExpired(projectId, token, env) {
  const started = Date.now();
  const now = new Date();
  const ago30 = new Date(now.getTime() - 30 * DAY_MS);
  let scanned = 0, emailsSent = 0; const errors = [];
  try {
    const members = await fsRunQuery(projectId, {
      from: [{ collectionId: 'members', allDescendants: true }],
      where: fAnd(
        fEq('access_status', { stringValue: 'active' }),
        fCmp('expiration_date', 'GREATER_THAN_OR_EQUAL', { timestampValue: ago30.toISOString() }),
        fCmp('expiration_date', 'LESS_THAN', { timestampValue: now.toISOString() }),
      ),
    }, token);
    scanned = members.length;

    // Agrupar por tenant
    const byTenant = {};
    for (const m of members) {
      if (!m.tenant_id) continue;
      (byTenant[m.tenant_id] ??= []).push(m);
    }

    for (const [tenantId, list] of Object.entries(byTenant)) {
      try {
        const tenant = await fsGet(projectId, `tenants/${tenantId}`, token);
        const gymName = tenant?.name ?? 'tu gimnasio';
        // Owners del tenant (single-field index: tenant_id), se filtra rol en código.
        const users = await fsRunQuery(projectId, {
          from: [{ collectionId: 'users' }],
          where: fEq('tenant_id', { stringValue: tenantId }),
        }, token);
        const owners = users.filter(
          (u) => u.role === 'owner' && u.status !== 'suspended' && u.email);
        for (const owner of owners) {
          const ok = await sendEmail(
            owner.email,
            `Socios vencidos sin renovar — ${gymName}`,
            ownerSummaryHtml(owner.name, gymName, list),
            env,
          );
          if (ok) emailsSent++;
        }
      } catch (e) { errors.push(`tenant ${tenantId}: ${e.message}`); }
    }
  } catch (e) { errors.push(e.message); }
  await logCronRun(projectId, token, {
    job: 'notify_owners_expired', ran_at: now, duration_ms: Date.now() - started,
    scanned, updated: 0, emails_sent: emailsSent, ok: errors.length === 0, errors,
  });
}

// Job diario: avisa a los Owners cuya suscripción SaaS se renueva en ~3 días.
// La ventana [+2d, +3d) garantiza un único aviso por ciclo (corre cada día).
async function runNotifyOwnersUpcomingRenewal(projectId, token, env) {
  const started = Date.now();
  const now = new Date();
  const in2 = new Date(now.getTime() + 2 * DAY_MS);
  const in3 = new Date(now.getTime() + 3 * DAY_MS);
  let scanned = 0, emailsSent = 0; const errors = [];
  try {
    const tenants = await fsRunQuery(projectId, {
      from: [{ collectionId: 'tenants' }],
      where: fAnd(
        fEq('subscription_status', { stringValue: 'active' }),
        fCmp('billing_cycle_end', 'GREATER_THAN_OR_EQUAL', { timestampValue: in2.toISOString() }),
        fCmp('billing_cycle_end', 'LESS_THAN', { timestampValue: in3.toISOString() }),
      ),
    }, token);
    scanned = tenants.length;
    for (const t of tenants) {
      if (t.past_due === true) continue; // si ya está vencido, no recordamos renovación
      try {
        const owners = await tenantOwners(projectId, t.id, token);
        const fecha = new Date(t.billing_cycle_end).toLocaleDateString('es-MX');
        for (const o of owners) {
          const ok = await sendEmail(
            o.email,
            `Tu suscripción se renueva pronto — ${t.name}`,
            renewalReminderHtml(o.name, t.name, fecha),
            env,
          );
          if (ok) emailsSent++;
        }
      } catch (e) { errors.push(`${t.path}: ${e.message}`); }
    }
  } catch (e) { errors.push(e.message); }
  await logCronRun(projectId, token, {
    job: 'notify_owners_renewal', ran_at: now, duration_ms: Date.now() - started,
    scanned, updated: 0, emails_sent: emailsSent, ok: errors.length === 0, errors,
  });
}

async function handleScheduled(event, env) {
  const token = await getAdminToken(env);
  const projectId = JSON.parse(env.SA_JSON).project_id;
  switch (event.cron) {
    case '0 9 * * *': // 03:00 MX — mantenimiento diario de estados
      await runMarkDebtors(projectId, token);
      await runMarkPastDueTenants(projectId, token);
      await runNotifyOwnersUpcomingRenewal(projectId, token, env);
      break;
    case '0 15 * * 1': // 09:00 MX lunes — notificaciones semanales
      await runNotifyExpiringMembers(projectId, token, env);
      await runNotifyOwnersExpired(projectId, token, env);
      break;
    default:
      console.warn('[scheduled] cron no reconocido:', event.cron);
  }
}

// ── Stripe (facturación SaaS B2B) ───────────────────────────────────────────

// Codifica un objeto a application/x-www-form-urlencoded con notación de Stripe
// (items[0][price]=..., metadata[tenant_id]=..., expand[0]=...).
function stripeForm(obj, prefix = '', out = new URLSearchParams()) {
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    const key = prefix ? `${prefix}[${k}]` : k;
    if (Array.isArray(v)) {
      v.forEach((item, i) => {
        if (item !== null && typeof item === 'object') stripeForm(item, `${key}[${i}]`, out);
        else out.append(`${key}[${i}]`, String(item));
      });
    } else if (typeof v === 'object') {
      stripeForm(v, key, out);
    } else {
      out.append(key, String(v));
    }
  }
  return out;
}

async function stripeRequest(path, params, env, method = 'POST') {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${env.STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: method === 'GET' ? undefined : stripeForm(params).toString(),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Stripe ${path}: ${JSON.stringify(data?.error ?? data)}`);
  return data;
}

// Verifica la firma del webhook de Stripe (HMAC-SHA256 sobre `${t}.${payload}`).
async function verifyStripeSig(payload, sigHeader, secret) {
  const items = sigHeader.split(',').map((p) => p.split('='));
  const t = items.find(([k]) => k === 't')?.[1];
  const v1s = items.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!t || v1s.length === 0) return false;

  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key,
    new TextEncoder().encode(`${t}.${payload}`));
  const expected = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0')).join('');

  // Tolerancia de 5 min contra replay.
  const age = Math.abs(Math.floor(Date.now() / 1000) - parseInt(t, 10));
  if (age > 300) return false;

  // Comparación en tiempo (casi) constante.
  return v1s.some((v) => {
    if (v.length !== expected.length) return false;
    let diff = 0;
    for (let i = 0; i < v.length; i++) diff |= v.charCodeAt(i) ^ expected.charCodeAt(i);
    return diff === 0;
  });
}

// Busca el tenant dueño de un Customer de Stripe (índice de campo único auto).
async function findTenantByCustomer(projectId, customerId, token) {
  if (!customerId) return null;
  const rows = await fsRunQuery(projectId, {
    from: [{ collectionId: 'tenants' }],
    where: fEq('stripe_customer_id', { stringValue: customerId }),
    limit: 1,
  }, token);
  return rows[0] ?? null;
}

async function handleStripeWebhook(request, env) {
  if (!env.STRIPE_WEBHOOK_SECRET) {
    return jsonRes({ error: 'STRIPE_WEBHOOK_SECRET no configurado' }, 503);
  }
  const payload = await request.text();
  const sig = request.headers.get('stripe-signature') ?? '';
  if (!(await verifyStripeSig(payload, sig, env.STRIPE_WEBHOOK_SECRET))) {
    return jsonRes({ error: 'Firma inválida' }, 400);
  }

  const event = JSON.parse(payload);
  const token = await getAdminToken(env);
  const projectId = JSON.parse(env.SA_JSON).project_id;

  // Idempotencia: si ya procesamos este evento, salir OK.
  if (await fsGet(projectId, `stripe_events/${event.id}`, token)) {
    return jsonRes({ received: true, duplicate: true });
  }
  await fsSet(projectId, `stripe_events/${event.id}`,
    { type: event.type, received_at: new Date() }, token);

  const obj = event.data.object;
  try {
    switch (event.type) {
      case 'invoice.paid':
      case 'invoice.payment_succeeded': {
        const tenant = await findTenantByCustomer(projectId, obj.customer, token);
        if (tenant) {
          const line = obj.lines?.data?.[0];
          const periodEnd = line?.period?.end;
          // package_price_id es la señal real de "tiene plan SaaS pagado":
          // solo se escribe tras un cobro confirmado (no en el alta del gym).
          const priceId = line?.price?.id ?? line?.plan?.id;
          const upd = {
            subscription_status: 'active',
            stripe_subscription_status: 'active',
            past_due: false,
          };
          if (periodEnd) upd.billing_cycle_end = new Date(periodEnd * 1000);
          if (priceId) upd.package_price_id = priceId;
          await fsUpdate(projectId, tenant.path, upd, token);
          await fsSet(projectId, `tenant_invoices/${obj.id}`, {
            tenant_id: tenant.id,
            stripe_invoice_id: obj.id,
            amount: (obj.amount_paid ?? 0) / 100,
            currency: obj.currency,
            status: 'paid',
            created_at: new Date(),
          }, token);
        }
        break;
      }
      case 'invoice.payment_failed': {
        const tenant = await findTenantByCustomer(projectId, obj.customer, token);
        if (tenant) {
          await fsUpdate(projectId, tenant.path, { past_due: true }, token);
          // Avisa a los Owners (best-effort; un fallo de email no debe romper el webhook).
          try {
            const owners = await tenantOwners(projectId, tenant.id, token);
            for (const o of owners) {
              await sendEmail(o.email, `Pago rechazado — ${tenant.name}`,
                paymentFailedHtml(o.name, tenant.name), env);
            }
          } catch (e) { console.error('[webhook] notify payment_failed:', e.message); }
        }
        break;
      }
      // Alta y cambios de la suscripción (incluye el periodo de prueba).
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const tenant = await findTenantByCustomer(projectId, obj.customer, token);
        if (tenant) {
          const status = obj.status; // trialing | active | past_due | unpaid | canceled | …
          const priceId = obj.items?.data?.[0]?.price?.id;
          const periodEnd = obj.current_period_end;
          const upd = { stripe_subscription_status: status };
          if (priceId) upd.package_price_id = priceId;
          if (periodEnd) upd.billing_cycle_end = new Date(periodEnd * 1000);
          if (status === 'active' || status === 'trialing') {
            upd.subscription_status = 'active';
            upd.past_due = false;
          } else if (status === 'past_due' || status === 'unpaid') {
            upd.past_due = true;
          } else if (status === 'canceled') {
            upd.subscription_status = 'cancelled';
          }
          if (status === 'trialing') upd.trial_used = true; // prueba consumida
          await fsUpdate(projectId, tenant.path, upd, token);
        }
        break;
      }
      case 'customer.subscription.deleted': {
        const tenant = await findTenantByCustomer(projectId, obj.customer, token);
        if (tenant) {
          await fsUpdate(projectId, tenant.path, {
            subscription_status: 'cancelled',
            stripe_subscription_status: 'canceled',
          }, token);
        }
        break;
      }
      default:
        break; // otros eventos se ignoran
    }
  } catch (e) {
    console.error('[webhook]', event.type, e.message);
    return jsonRes({ error: e.message }, 500); // 5xx → Stripe reintenta
  }
  return jsonRes({ received: true });
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(handleScheduled(event, env));
  },

  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    const { pathname } = new URL(request.url);

    // ── POST /billing/webhook ───────────────────────────────────────────────────
    // ANTES de checkAuth: Stripe firma con su propio secreto, no manda el Bearer.
    if (request.method === 'POST' && pathname === '/billing/webhook') {
      return handleStripeWebhook(request, env);
    }

    if (!checkAuth(request, env)) {
      return jsonRes({ error: 'Unauthorized' }, 401);
    }

    // ── POST /upload ──────────────────────────────────────────────────────────
    if (request.method === 'POST' && pathname === '/upload') {
      const formData = await request.formData();
      const file = formData.get('file');
      const key  = formData.get('key');
      if (!file || !key) return jsonRes({ error: 'Missing file or key' }, 400);

      const bytes = await file.arrayBuffer();
      await env.R2_BUCKET.put(key, bytes, {
        httpMetadata: { contentType: file.type || 'application/octet-stream' },
      });
      return jsonRes({ url: `${env.R2_PUBLIC_BASE ?? 'https://pub-c1dbef6de1ab47f1a5697445f13f6aec.r2.dev'}/${key}`, key });
    }

    // ── DELETE /delete ────────────────────────────────────────────────────────
    if (request.method === 'DELETE' && pathname === '/delete') {
      const { key } = await request.json();
      if (!key) return jsonRes({ error: 'Missing key' }, 400);
      await env.R2_BUCKET.delete(key);
      return jsonRes({ success: true });
    }

    // ── GET /catalogs/postal?cp=XXXXX ───────────────────────────────────────────
    // Catálogo SEPOMEX en Cloudflare D1: dado un CP devuelve estado/municipio/
    // ciudad y la lista de colonias. Desbloquea el autocompletado fiscal (#16).
    if (request.method === 'GET' && pathname === '/catalogs/postal') {
      const cp = new URL(request.url).searchParams.get('cp') ?? '';
      if (!/^\d{5}$/.test(cp)) {
        return jsonRes({ error: 'cp inválido (5 dígitos)' }, 400);
      }
      if (!env.CATALOGS_DB) {
        return jsonRes({ error: 'Catálogo no disponible (D1 sin configurar)' }, 503);
      }
      const { results } = await env.CATALOGS_DB
        .prepare('SELECT estado, municipio, ciudad, asentamiento, tipo FROM sepomex WHERE cp = ? ORDER BY asentamiento')
        .bind(cp)
        .all();
      if (!results || results.length === 0) {
        return jsonRes({ cp, found: false, colonias: [] });
      }
      const f = results[0];
      return jsonRes({
        cp,
        found: true,
        estado: f.estado,
        municipio: f.municipio,
        ciudad: f.ciudad,
        colonias: results.map((r) => ({ nombre: r.asentamiento, tipo: r.tipo })),
      });
    }

    // ── POST /billing/checkout ──────────────────────────────────────────────────
    // Crea (o reutiliza) el Customer del tenant y abre un Checkout hospedado de
    // Stripe en modo suscripción. Devuelve la URL a la que redirige la app.
    if (request.method === 'POST' && pathname === '/billing/checkout') {
      if (!env.STRIPE_SECRET_KEY) {
        return jsonRes({ error: 'STRIPE_SECRET_KEY no configurado' }, 503);
      }
      const { tenantId, priceId, successUrl, cancelUrl } = await request.json();
      if (!tenantId || !priceId) {
        return jsonRes({ error: 'Faltan tenantId o priceId' }, 400);
      }
      const token = await getAdminToken(env);
      const projectId = JSON.parse(env.SA_JSON).project_id;
      const tenant = await fsGet(projectId, `tenants/${tenantId}`, token);
      if (!tenant) return jsonRes({ error: 'Tenant no encontrado' }, 404);

      let customerId = tenant.stripe_customer_id;
      if (!customerId) {
        const customer = await stripeRequest('customers', {
          email: tenant.email,
          name: tenant.name,
          metadata: { tenant_id: tenantId },
        }, env);
        customerId = customer.id;
        await fsUpdate(projectId, `tenants/${tenantId}`,
          { stripe_customer_id: customerId }, token);
      }

      const fallback = `${env.WORKER_BASE_URL ?? 'https://omni-gym.hadith024.workers.dev'}/billing/done`;
      // Prueba gratis: Stripe guarda la tarjeta pero no cobra hasta el día N.
      // Solo la primera vez (trial_used evita reactivar prueba al re-suscribirse).
      const trialDays = parseInt(env.TRIAL_DAYS ?? '14', 10);
      const subData = { metadata: { tenant_id: tenantId } };
      if (!tenant.trial_used && trialDays > 0) subData.trial_period_days = trialDays;
      const session = await stripeRequest('checkout/sessions', {
        mode: 'subscription',
        customer: customerId,
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: successUrl ?? fallback,
        cancel_url: cancelUrl ?? fallback,
        subscription_data: subData,
        metadata: { tenant_id: tenantId },
      }, env);
      return jsonRes({ url: session.url, sessionId: session.id });
    }

    // ── POST /billing/portal ────────────────────────────────────────────────────
    // Abre el Customer Portal de Stripe para que el Owner gestione/cancele.
    if (request.method === 'POST' && pathname === '/billing/portal') {
      if (!env.STRIPE_SECRET_KEY) {
        return jsonRes({ error: 'STRIPE_SECRET_KEY no configurado' }, 503);
      }
      const { tenantId, returnUrl } = await request.json();
      if (!tenantId) return jsonRes({ error: 'Falta tenantId' }, 400);
      const token = await getAdminToken(env);
      const projectId = JSON.parse(env.SA_JSON).project_id;
      const tenant = await fsGet(projectId, `tenants/${tenantId}`, token);
      if (!tenant?.stripe_customer_id) {
        return jsonRes({ error: 'El tenant no tiene suscripción activa' }, 400);
      }
      const session = await stripeRequest('billing_portal/sessions', {
        customer: tenant.stripe_customer_id,
        return_url: returnUrl ?? `${env.WORKER_BASE_URL ?? 'https://omni-gym.hadith024.workers.dev'}/billing/done`,
      }, env);
      return jsonRes({ url: session.url });
    }

    // ── POST /billing/packages ──────────────────────────────────────────────────
    // Crea un paquete: producto + precio recurrente en Stripe y doc en Firestore.
    if (request.method === 'POST' && pathname === '/billing/packages') {
      if (!env.STRIPE_SECRET_KEY) {
        return jsonRes({ error: 'STRIPE_SECRET_KEY no configurado' }, 503);
      }
      const { name, price, interval = 'month', limits = {} } = await request.json();
      if (!name || !(price > 0)) {
        return jsonRes({ error: 'Faltan name o price (> 0)' }, 400);
      }
      const token = await getAdminToken(env);
      const projectId = JSON.parse(env.SA_JSON).project_id;

      const product = await stripeRequest('products', { name }, env);
      const stripePrice = await stripeRequest('prices', {
        product: product.id,
        unit_amount: Math.round(price * 100),
        currency: 'mxn',
        recurring: { interval },
      }, env);

      const id = crypto.randomUUID();
      const doc = {
        name,
        price,
        currency: 'mxn',
        interval,
        stripe_product_id: product.id,
        stripe_price_id: stripePrice.id,
        limit_branches: limits.branches ?? null,
        limit_checkins: limits.checkins ?? null,
        limit_staff: limits.staff ?? null,
        active: true,
        created_at: new Date(),
      };
      await fsSet(projectId, `subscription_packages/${id}`, doc, token);
      return jsonRes({ id, ...doc });
    }

    // ── POST /billing/packages/update ─────────────────────────────────────────────
    // Actualiza nombre/límites/activo. Si cambia el precio, crea un nuevo Stripe
    // price y archiva el anterior (los precios de Stripe son inmutables).
    if (request.method === 'POST' && pathname === '/billing/packages/update') {
      if (!env.STRIPE_SECRET_KEY) {
        return jsonRes({ error: 'STRIPE_SECRET_KEY no configurado' }, 503);
      }
      const { id, name, price, active, limits } = await request.json();
      if (!id) return jsonRes({ error: 'Falta id' }, 400);
      const token = await getAdminToken(env);
      const projectId = JSON.parse(env.SA_JSON).project_id;
      const pkg = await fsGet(projectId, `subscription_packages/${id}`, token);
      if (!pkg) return jsonRes({ error: 'Paquete no encontrado' }, 404);

      const upd = {};
      if (name && name !== pkg.name) {
        await stripeRequest(`products/${pkg.stripe_product_id}`, { name }, env);
        upd.name = name;
      }
      if (limits) {
        if (limits.branches !== undefined) upd.limit_branches = limits.branches;
        if (limits.checkins !== undefined) upd.limit_checkins = limits.checkins;
        if (limits.staff !== undefined) upd.limit_staff = limits.staff;
      }
      if (typeof active === 'boolean' && active !== pkg.active) {
        // Archiva/reactiva el precio en Stripe para que no se pueda contratar.
        await stripeRequest(`prices/${pkg.stripe_price_id}`, { active }, env);
        upd.active = active;
      }
      if (price > 0 && price !== pkg.price) {
        await stripeRequest(`prices/${pkg.stripe_price_id}`, { active: false }, env);
        const newPrice = await stripeRequest('prices', {
          product: pkg.stripe_product_id,
          unit_amount: Math.round(price * 100),
          currency: 'mxn',
          recurring: { interval: pkg.interval ?? 'month' },
        }, env);
        upd.stripe_price_id = newPrice.id;
        upd.price = price;
      }
      if (Object.keys(upd).length > 0) {
        await fsUpdate(projectId, `subscription_packages/${id}`, upd, token);
      }
      return jsonRes({ id, ...pkg, ...upd });
    }

    // ── POST /set-claims ──────────────────────────────────────────────────────
    if (request.method === 'POST' && pathname === '/set-claims') {
      const { uid, role, tenant_id, branch_id } = await request.json();
      if (!uid || !role || !tenant_id) {
        return jsonRes({ error: 'Missing uid, role or tenant_id' }, 400);
      }

      const token = await getAdminToken(env);
      const claims = { role, tenant_id };
      if (branch_id) claims.branch_id = branch_id;
      await setCustomClaims(uid, claims, token);

      return jsonRes({ success: true });
    }

    // ── POST /create-staff ────────────────────────────────────────────────────
    if (request.method === 'POST' && pathname === '/create-staff') {
      const { name, email, role, tenant_id, branch_id, gymName, csd_cargo } = await request.json();
      if (!name || !email || !role || !tenant_id) {
        return jsonRes({ error: 'Missing required fields' }, 400);
      }

      const token = await getAdminToken(env);
      const sa = JSON.parse(env.SA_JSON);
      const projectId = sa.project_id;

      // 1. Crear usuario en Auth (sin contraseña; la define él mismo por email)
      let uid;
      try {
        uid = await createAuthUser(email, name, token);
      } catch (e) {
        const msg = e.message ?? '';
        if (msg.includes('EMAIL_EXISTS') || msg.includes('email-already-exists')) {
          return jsonRes({ error: 'Ya existe una cuenta registrada con ese correo electrónico.' }, 409);
        }
        throw e;
      }

      // 2. Custom claims (role, tenant_id, branch_id?)
      const claims = { role, tenant_id };
      if (branch_id) claims.branch_id = branch_id;
      await setCustomClaims(uid, claims, token);

      // 3. Documento /users/{uid} server-side con info del staff 
      await fsSet(projectId, `users/${uid}`, {
        name,
        email,
        role,
        status: 'active',
        tenant_id,
        branch_id: branch_id || null,
        csd_cargo: csd_cargo || null,
        created_at: new Date(),
      }, token);

      // 4. Email de invitación: Resend con marca (enlace de set-password);
      //    si no hay Resend o falla, fallback al correo de Firebase.
      let emailSent = false;
      if (env.RESEND_API_KEY) {
        const link = await generatePasswordResetLink(email, token);
        const roleLabel = role === 'owner' ? 'administrador' : 'recepcionista';
        emailSent = await sendStaffInviteEmail(
            email, name, gymName ?? 'OmniGym', roleLabel, link, env);
      }
      if (!emailSent) {
        await sendPasswordReset(email, env);
      }

      return jsonRes({ uid });
    }

    // ── POST /delete-staff ──────────────────────────────────────────────────────
    // Borra la cuenta de Firebase Auth y el documento /users/{uid} de un operador.
    // Body: { uid }
    if (request.method === 'POST' && pathname === '/delete-staff') {
      const { uid } = await request.json();
      if (!uid) return jsonRes({ error: 'Missing uid' }, 400);

      const token = await getAdminToken(env);
      const sa = JSON.parse(env.SA_JSON);
      const projectId = sa.project_id;

      // Borra el doc primero (idempotente); luego la cuenta de Auth.
      await fsDelete(projectId, `users/${uid}`, token);
      try {
        await deleteAuthUser(uid, token);
      } catch (e) {
        // Si la cuenta ya no existe en Auth, lo consideramos éxito.
        const msg = e.message ?? '';
        if (!msg.includes('USER_NOT_FOUND')) throw e;
      }

      return jsonRes({ success: true });
    }

    // ── POST /create-member ───────────────────────────────────────────────────
    // Crea una cuenta Firebase Auth + documento Firestore para un socio y
    // envía un email con la contraseña temporal vía Resend.
    // Body: { tenantId, name, email, phone?, expirationDate (ISO), allowedBranches, gymName? }
    // Requires env: SA_JSON, RESEND_API_KEY, EMAIL_FROM?
    if (request.method === 'POST' && pathname === '/create-member') {
      const { tenantId, name, email, phone, expirationDate, allowedBranches, gymName } =
        await request.json();

      if (!tenantId || !name || !email || !expirationDate || !allowedBranches?.length) {
        return jsonRes({ error: 'Faltan campos requeridos: tenantId, name, email, expirationDate, allowedBranches.' }, 400);
      }

      const token = await getAdminToken(env);
      const sa = JSON.parse(env.SA_JSON);
      const projectId = sa.project_id;

      // 1. Contraseña temporal y QR token
      const tempPassword = generateTempPassword();
      const qrToken = generateQrToken();

      // 2. Crear usuario en Firebase Auth con contraseña
      let uid;
      try {
        uid = await createMemberAuth(projectId, email, name, tempPassword, token);
      } catch (e) {
        const msg = e.message ?? '';
        if (msg.includes('EMAIL_EXISTS') || msg.includes('email-already-exists')) {
          return jsonRes({ error: 'Ya existe una cuenta registrada con ese correo electrónico.' }, 409);
        }
        throw e;
      }

      // 3. Custom claims para el miembro (role: member)
      await setCustomClaims(uid, { role: 'member', tenant_id: tenantId }, token);

      // 4. Crear documento en Firestore
      await fsSet(projectId, `tenants/${tenantId}/members/${uid}`, {
        uid,
        tenant_id: tenantId,
        name,
        email,
        phone: phone || null,
        qr_token: qrToken,
        expiration_date: new Date(expirationDate),
        allowed_branches: allowedBranches,
        access_status: 'active',
        plan_id: null,
        created_at: new Date(),
      }, token);

      // 5. Email: intenta Resend si hay API key; si falla o no hay key,
      //    usa el email de Firebase (password reset) como fallback.
      let emailSent = false;
      if (env.RESEND_API_KEY) {
        emailSent = await sendWelcomeEmail(email, name, tempPassword, gymName ?? 'OmniGym', env);
      }
      if (!emailSent) {
        await sendPasswordReset(email, env);
      }

      // Devuelve tempPassword para que el recepcionista pueda comunicársela al socio.
      return jsonRes({ uid, qrToken, tempPassword });
    }

    return jsonRes({ error: 'Not found' }, 404);
  },
};

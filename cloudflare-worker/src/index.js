const PUBLIC_BASE = 'https://pub-c1dbef6de1ab47f1a5697445f13f6aec.r2.dev';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, DELETE, OPTIONS',
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

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (!checkAuth(request, env)) {
      return jsonRes({ error: 'Unauthorized' }, 401);
    }

    const { pathname } = new URL(request.url);

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
      return jsonRes({ url: `${PUBLIC_BASE}/${key}`, key });
    }

    // ── DELETE /delete ────────────────────────────────────────────────────────
    if (request.method === 'DELETE' && pathname === '/delete') {
      const { key } = await request.json();
      if (!key) return jsonRes({ error: 'Missing key' }, 400);
      await env.R2_BUCKET.delete(key);
      return jsonRes({ success: true });
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

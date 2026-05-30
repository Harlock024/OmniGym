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
  // SA_JSON es el contenido completo del JSON de service account de Firebase
  const sa = JSON.parse(env.SA_JSON);
  const saEmail      = sa.client_email;
  const saPrivateKey = sa.private_key; // ya tiene \n reales en el JSON parseado

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
  return data.localId; // UID del nuevo usuario
}

async function setCustomClaims(uid, claims, token) {
  await fbAuthPost('update', {
    localId: uid,
    customAttributes: JSON.stringify(claims),
  }, token);
}

async function sendPasswordReset(email, token) {
  await fbAuthPost('sendOobCode', {
    requestType: 'PASSWORD_RESET',
    email,
  }, token);
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
    // Asigna custom claims a un usuario existente de Firebase Auth.
    // Body: { uid, role, tenant_id, branch_id? }
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
    // Crea un usuario en Firebase Auth, asigna claims y envía email de contraseña.
    // Body: { name, email, role, tenant_id, branch_id? }
    // Returns: { uid }
    if (request.method === 'POST' && pathname === '/create-staff') {
      const { name, email, role, tenant_id, branch_id } = await request.json();
      if (!name || !email || !role || !tenant_id) {
        return jsonRes({ error: 'Missing required fields' }, 400);
      }

      const token = await getAdminToken(env);

      // 1. Crear usuario
      const uid = await createAuthUser(email, name, token);

      // 2. Custom claims
      const claims = { role, tenant_id };
      if (branch_id) claims.branch_id = branch_id;
      await setCustomClaims(uid, claims, token);

      // 3. Email para que el operador configure su contraseña
      await sendPasswordReset(email, token);

      return jsonRes({ uid });
    }

    return jsonRes({ error: 'Not found' }, 404);
  },
};

const PUBLIC_BASE = 'https://pub-c1dbef6de1ab47f1a5697445f13f6aec.r2.dev';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function unauthorized() {
  return json({ error: 'Unauthorized' }, 401);
}

function checkAuth(request, env) {
  const auth = request.headers.get('Authorization') ?? '';
  return auth === `Bearer ${env.UPLOAD_SECRET}`;
}

export default {
  async fetch(request, env) {
    // Preflight CORS
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (!checkAuth(request, env)) return unauthorized();

    const { pathname } = new URL(request.url);

    // ── POST /upload ────────────────────────────────────────────────────────
    if (request.method === 'POST' && pathname === '/upload') {
      const formData = await request.formData();
      const file = formData.get('file');
      const key  = formData.get('key');

      if (!file || !key) {
        return json({ error: 'Missing file or key' }, 400);
      }

      const bytes = await file.arrayBuffer();
      await env.R2_BUCKET.put(key, bytes, {
        httpMetadata: { contentType: file.type || 'application/octet-stream' },
      });

      return json({ url: `${PUBLIC_BASE}/${key}`, key });
    }

    // ── DELETE /delete ──────────────────────────────────────────────────────
    if (request.method === 'DELETE' && pathname === '/delete') {
      const { key } = await request.json();
      if (!key) return json({ error: 'Missing key' }, 400);
      await env.R2_BUCKET.delete(key);
      return json({ success: true });
    }

    return json({ error: 'Not found' }, 404);
  },
};

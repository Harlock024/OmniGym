import { hasModule, canManageUser } from './module_access.js';

export class AccessError extends Error {
  constructor(message, status = 403) { super(message); this.status = status; }
}

function requireAccess(condition) {
  if (!condition) throw new AccessError('No tienes permiso para esta operación.');
}

// Firebase validates signature, expiry and account state. We additionally bind the
// result to this project's audience/issuer and read the live authorization profile.
// https://firebase.google.com/docs/reference/rest/auth#section-get-account-info
export async function authenticate(request, env, loadProfile) {
  const idToken = request.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];
  if (!idToken || idToken.split('.').length !== 3) throw new AccessError('Inicia sesión para continuar.', 401);
  const key = env.FIREBASE_API_KEY;
  if (!key) throw new AccessError('FIREBASE_API_KEY no configurado.', 503);
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(key)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ idToken }),
  });
  const account = res.ok ? (await res.json()).users?.[0] : null;
  if (!account?.localId || account.disabled) throw new AccessError('La sesión no es válida. Inicia sesión nuevamente.', 401);
  let claims;
  try {
    const part = idToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    claims = JSON.parse(atob(part.padEnd(Math.ceil(part.length / 4) * 4, '=')));
  } catch { throw new AccessError('La sesión no es válida.', 401); }
  const projectId = JSON.parse(env.SA_JSON).project_id;
  if (claims.sub !== account.localId || claims.aud !== projectId ||
      claims.iss !== `https://securetoken.google.com/${projectId}` ||
      !Number.isFinite(claims.exp) || claims.exp <= Date.now() / 1000 ||
      (account.validSince && claims.auth_time < Number(account.validSince))) {
    throw new AccessError('La sesión no es válida.', 401);
  }
  const profile = await loadProfile(`users/${account.localId}`);
  if (profile && profile.status !== 'active') throw new AccessError('Tu acceso está suspendido.');
  return { ...(profile ?? { role: 'member', status: 'active' }), uid: account.localId };
}

export async function authorize(request, actor, loadDocument) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (['/catalogs/postal', '/geocode/search'].includes(path)) return;
  let body = {};
  if (request.method === 'POST' && path !== '/upload') {
    try { body = await request.clone().json(); }
    catch { throw new AccessError('JSON inválido.', 400); }
  }
  // Use exactly the field consumed by the handler; aliases must not authorize
  // one gym while the handler writes to another.
  const tenantId = path === '/create-staff' ? body.tenant_id : body.tenantId ?? url.searchParams.get('tenantId');
  const owner = id => actor.role === 'superuser' || (actor.role === 'owner' && actor.tenant_id === id);
  const module = (id, name) => actor.role === 'superuser' || (id && actor.tenant_id === id && hasModule(actor, name));

  if (path === '/set-claims') {
    requireAccess(actor.role === 'superuser' || (actor.uid === body.uid && actor.role === body.role && actor.tenant_id === body.tenant_id && (actor.branch_id ?? null) === (body.branch_id ?? null)));
    requireAccess(['superuser', 'owner', 'staff', 'receptionist', 'member'].includes(body.role));
    return;
  }
  if (path === '/create-staff') {
    requireAccess(['staff', 'receptionist'].includes(body.role));
    requireAccess(owner(tenantId) || (actor.role === 'staff' && actor.tenant_id === tenantId && body.role === 'receptionist'));
    requireAccess(typeof body.branch_id === 'string' && !!await loadDocument(`tenants/${tenantId}/branches/${body.branch_id}`));
    return;
  }
  if (path === '/delete-staff') {
    requireAccess(canManageUser(actor, await loadDocument(`users/${body.uid}`)));
    return;
  }
  if (path === '/create-member') {
    requireAccess(module(tenantId, 'members'));
    return;
  }
  if (path === '/billing/checkout' || path === '/billing/portal') {
    requireAccess(owner(tenantId));
    return;
  }
  if (path === '/billing/packages' || path === '/billing/packages/update') {
    requireAccess(actor.role === 'superuser');
    return;
  }
  if (path.startsWith('/facturacion/')) {
    if (path === '/facturacion/status') requireAccess(hasModule(actor, 'billing'));
    else if (actor.role === 'member' && path === '/facturacion/invoice')
      requireAccess(!!await loadDocument(`tenants/${tenantId}/members/${actor.uid}`));
    else requireAccess(module(tenantId, 'billing'));
    return;
  }
  if (path === '/upload' || path === '/delete') {
    let key;
    if (path === '/upload') key = (await request.clone().formData()).get('key');
    else {
      try { key = (await request.clone().json()).key; }
      catch { throw new AccessError('JSON inválido.', 400); }
    }
    requireAccess(typeof key === 'string');
    const selfPhoto = key === `profile_photos/${actor.uid}.jpg`;
    const match = key.match(/^(tenant_logos|tenant_csd)\/([^/]+)\/[^/]+$/);
    requireAccess(selfPhoto || (match && owner(match[2])));
  }
}

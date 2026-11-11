import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authenticate, authorize } from '../src/authorization.js';
import { initialPermissions, hasModule } from '../src/module_access.js';
import worker from '../src/index.js';

const actor = (role, permissions = {}) => ({ uid: 'actor', id: 'actor', role, tenant_id: 'gym', status: 'active', permissions });
const request = (path, body) => new Request(`https://worker.test${path}`, body ? {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
} : {});
const denied = operation => assert.rejects(operation, error => error.status === 403);

test('receptionists start with every module disabled; Staff preserves baseline', () => {
  const permissions = initialPermissions('receptionist');
  assert.equal(Object.values(permissions).some(Boolean), false);
  assert.equal(hasModule(actor('receptionist', permissions), 'scanner'), false);
  assert.equal(hasModule(actor('staff'), 'scanner'), true);
  assert.equal(hasModule(actor('staff', { scanner: false }), 'scanner'), false);
});
test('disabled billing and forged tenant IDs cannot call billing endpoints', async () => {
  await denied(() => authorize(request('/facturacion/timbrar', { tenantId: 'gym' }), actor('receptionist'), async () => null));
  await authorize(request('/facturacion/timbrar', { tenantId: 'gym' }), actor('receptionist', { billing: true }), async () => null);
  await denied(() => authorize(request('/facturacion/timbrar', { tenantId: 'other' }), actor('receptionist', { billing: true }), async () => null));
});
test('conflicting tenant aliases cannot authorize a write to another gym', async () => {
  await denied(() => authorize(request('/create-staff', { tenantId: 'gym', tenant_id: 'other', role: 'staff', branch_id: 'b' }), actor('owner'), async () => ({ id: 'b' })));
});
test('staff cannot invite Owners, promote another Staff or delete an Owner', async () => {
  const staff = actor('staff');
  const branch = async () => ({ id: 'branch' });
  await authorize(request('/create-staff', { tenant_id: 'gym', role: 'receptionist', branch_id: 'branch' }), staff, branch);
  for (const role of ['owner', 'staff', 'superuser'])
    await denied(() => authorize(request('/create-staff', { tenant_id: 'gym', role, branch_id: 'branch' }), staff, branch));
  await denied(() => authorize(request('/delete-staff', { uid: 'owner' }), staff, async () => ({ id: 'owner', role: 'owner', tenant_id: 'gym' })));
});
test('receptionists cannot manage permissions through claims or upload another profile', async () => {
  const reception = actor('receptionist');
  await denied(() => authorize(request('/set-claims', { uid: 'actor', role: 'owner', tenant_id: 'gym' }), reception, async () => null));
  const form = new FormData(); form.set('key', 'profile_photos/victim.jpg');
  await denied(() => authorize(new Request('https://worker.test/upload', { method: 'POST', body: form }), reception, async () => null));
});
test('a bundled shared secret no longer authorizes Worker operations', async () => {
  const res = await worker.fetch(new Request('https://worker.test/create-staff', { method: 'POST', headers: { Authorization: 'Bearer old-shared-secret' } }), {});
  assert.equal(res.status, 401);
});
test('identity uses Firebase validation plus current profile instead of token roles', async () => {
  const originalFetch = globalThis.fetch;
  const claims = { sub: 'actor', aud: 'project', iss: 'https://securetoken.google.com/project', role: 'owner', exp: Math.floor(Date.now() / 1000) + 1000, auth_time: 100 };
  const token = `header.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.signature`;
  globalThis.fetch = async () => Response.json({ users: [{ localId: 'actor' }] });
  try {
    const current = await authenticate(new Request('https://worker.test', { headers: { Authorization: `Bearer ${token}` } }), { FIREBASE_API_KEY: 'test', SA_JSON: JSON.stringify({ project_id: 'project' }) }, async () => actor('receptionist'));
    assert.equal(current.role, 'receptionist');
    assert.equal(hasModule(current, 'billing'), false);
    globalThis.fetch = async () => Response.json({ error: 'INVALID_ID_TOKEN' }, { status: 400 });
    await assert.rejects(() => authenticate(new Request('https://worker.test', { headers: { Authorization: `Bearer ${token}` } }), { FIREBASE_API_KEY: 'test' }, async () => actor('owner')), error => error.status === 401);
  } finally { globalThis.fetch = originalFetch; }
});

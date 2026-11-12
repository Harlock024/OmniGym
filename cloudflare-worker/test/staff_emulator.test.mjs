import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import worker from '../src/index.js';

const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;

test('Worker creates, activates, recovers and suspends a work account through local Firebase APIs', { skip: !authHost || !firestoreHost }, async () => {
  assert.match(authHost, /^(127\.0\.0\.1|localhost):\d+$/);
  assert.match(firestoreHost, /^(127\.0\.0\.1|localhost):\d+$/);
  const project = 'demo-omnigym-roles';
  const originalFetch = globalThis.fetch;
  const realFetch = originalFetch.bind(globalThis);
  const authUrl = path => `http://${authHost}/identitytoolkit.googleapis.com/v1/${path}`;
  const fsUrl = path => `http://${firestoreHost}/v1/projects/${project}/databases/(default)/documents/${path}`;
  const post = (body, authorization) => ({ method: 'POST', headers: { 'Content-Type': 'application/json', ...(authorization ? { Authorization: authorization } : {}) }, body: JSON.stringify(body) });
  async function auth(path, body) {
    const response = await realFetch(authUrl(`${path}?key=fake-key`), post(body));
    const result = await response.json();
    assert.equal(response.status, 200, JSON.stringify(result));
    return result;
  }
  const suffix = crypto.randomUUID().slice(0, 8);
  const ownerEmail = `owner-${suffix}@example.test`;
  const owner = await auth('accounts:signUp', { email: ownerEmail, password: 'OwnerTest123!', returnSecureToken: true });
  async function seed(path, fields) {
    const response = await realFetch(fsUrl(path), { method: 'PATCH', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' }, body: JSON.stringify({ fields }) });
    assert.equal(response.status, 200);
  }
  const gymId = `work-gym-${suffix}`;
  await seed(`tenants/${gymId}`, { name: { stringValue: `Gym Local ${suffix}` } });
  await seed(`tenants/${gymId}/branches/b`, { name: { stringValue: 'Centro' } });
  await seed(`users/${owner.localId}`, { name: { stringValue: 'Owner' }, email: { stringValue: ownerEmail }, role: { stringValue: 'owner' }, tenant_id: { stringValue: gymId }, status: { stringValue: 'active' } });
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const env = { FIREBASE_API_KEY: 'fake-key', RESEND_API_KEY: 'test-no-delivery', APP_BASE_URL: 'https://app.example.test/',
    SA_JSON: JSON.stringify({ project_id: project, client_email: 'emulator@example.test', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) }) };
  const mail = [];
  globalThis.fetch = async (input, init) => {
    const url = new URL(input);
    if (url.hostname === 'oauth2.googleapis.com') return Response.json({ access_token: 'emulator-admin' });
    if (url.hostname === 'firestore.googleapis.com') return realFetch(`http://${firestoreHost}${url.pathname}${url.search}`, { ...init, headers: { ...init.headers, Authorization: 'Bearer owner' } });
    if (url.hostname === 'identitytoolkit.googleapis.com') return realFetch(`http://${authHost}/identitytoolkit.googleapis.com${url.pathname}${url.search || '?key=fake-key'}`, {
      ...init, headers: { ...init.headers, ...(init.headers?.Authorization ? { Authorization: 'Bearer owner' } : {}) },
    });
    if (url.hostname === 'api.resend.com') { mail.push(JSON.parse(init.body)); return Response.json({ id: 'local-email' }); }
    throw new Error(`Unexpected network destination: ${url.hostname}`);
  };
  async function call(path, body, token) {
    const init = post(body, token ? `Bearer ${token}` : undefined);
    init.headers['CF-Connecting-IP'] = `2001:db8::${suffix.slice(0, 4)}:${suffix.slice(4)}`;
    return worker.fetch(new Request(`https://worker.test${path}`, init), env);
  }
  const invitationParams = () => {
    const link = mail.at(-1).html.match(/href="([^"]+)"/)[1].replaceAll('&amp;', '&');
    return new URLSearchParams(new URL(link).hash.split('?')[1]);
  };
  try {
    const createdResponse = await call('/staff-accounts', { name: 'Ana', email: ownerEmail, role: 'receptionist', tenant_id: gymId, branch_id: 'b' }, owner.idToken);
    const created = await createdResponse.json();
    assert.equal(createdResponse.status, 200, JSON.stringify(created));
    assert.equal(created.email_sent, true, 'Local Auth must generate a password setup code');
    assert.deepEqual(mail[0].to, [ownerEmail]);
    assert.equal(created.username, `gymlocal${suffix}ana@omnigym.xyz`);
    // Upgrade a pending invitation from the previous internal-email format using
    // the real Auth update API, preserving the identity through acceptance.
    const legacyLogin = `legacy.${suffix}.ana`;
    const rename = await realFetch(authUrl('accounts:update?key=fake-key'), post({
      localId: created.uid, email: `${legacyLogin}@staff.omnigym.invalid`, targetProjectId: project,
    }, 'Bearer owner'));
    assert.equal(rename.status, 200);
    const oldProfile = await (await realFetch(fsUrl(`users/${created.uid}`), { headers: { Authorization: 'Bearer owner' } })).json();
    await seed(`users/${created.uid}`, { ...oldProfile.fields, username: { stringValue: legacyLogin } });
    const oldInvite = await (await realFetch(fsUrl(`staff_invitations/${created.uid}`), { headers: { Authorization: 'Bearer owner' } })).json();
    await seed(`staff_invitations/${created.uid}`, { ...oldInvite.fields, created_at: { stringValue: new Date(Date.now() - 61_000).toISOString() } });
    const resentResponse = await call('/staff-invitations/resend', { uid: created.uid }, owner.idToken);
    const resent = await resentResponse.json();
    assert.equal(resentResponse.status, 200, JSON.stringify(resent));
    assert.equal(resent.username, created.username);
    assert.equal(resent.email_sent, true);
    const params = invitationParams();
    assert.equal((await call('/staff-invitations/preview', { id: created.uid, token: params.get('token') })).status, 200);
    const identity = created.username;
    const verification = await auth('accounts:resetPassword', { oobCode: params.get('oobCode') });
    assert.equal(verification.email, identity);
    await auth('accounts:resetPassword', { oobCode: params.get('oobCode'), newPassword: 'WorkTest123!' });
    const employee = await auth('accounts:signInWithPassword', { email: identity, password: 'WorkTest123!', returnSecureToken: true });
    assert.equal(employee.localId, created.uid);
    assert.equal((await call('/facturacion/status', {}, employee.idToken)).status, 403);
    const accept = await call('/staff-invitations/accept', { id: created.uid, token: params.get('token') }, employee.idToken);
    assert.equal(accept.status, 200, JSON.stringify(await accept.json()));
    assert.equal((await call('/staff-invitations/accept', { id: created.uid, token: params.get('token') }, employee.idToken)).status, 200);
    const profile = await (await realFetch(fsUrl(`users/${created.uid}`), { headers: { Authorization: 'Bearer owner' } })).json();
    assert.equal(profile.fields.status.stringValue, 'active');
    assert.equal(profile.fields.email.stringValue, ownerEmail);
    assert.equal(profile.fields.permissions.mapValue.fields.members.booleanValue, false);
    assert.equal((await call('/staff-password-recovery', { username: created.username })).status, 200);
    assert.equal(mail.length, 3);
    assert.deepEqual(mail[2].to, [ownerEmail]);
    const recovery = invitationParams();
    await auth('accounts:resetPassword', { oobCode: recovery.get('oobCode'), newPassword: 'NewWorkTest123!' });
    const duplicateReset = await realFetch(authUrl('accounts:resetPassword?key=fake-key'), post({ oobCode: recovery.get('oobCode'), newPassword: 'OtherPassword123!' }));
    assert.equal(duplicateReset.status, 400);
    const recovered = await auth('accounts:signInWithPassword', { email: identity, password: 'NewWorkTest123!', returnSecureToken: true });
    assert.equal((await call('/staff-accounts/deactivate', { uid: created.uid }, owner.idToken)).status, 200);
    assert.equal((await call('/facturacion/status', {}, recovered.idToken)).status, 403);
    const preserved = await (await realFetch(fsUrl(`users/${created.uid}`), { headers: { Authorization: 'Bearer owner' } })).json();
    assert.equal(preserved.fields.status.stringValue, 'suspended');
    const personal = await auth('accounts:signInWithPassword', { email: ownerEmail, password: 'OwnerTest123!', returnSecureToken: true });
    assert.equal(personal.localId, owner.localId);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

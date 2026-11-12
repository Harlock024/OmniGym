import { test } from 'node:test';
import assert from 'node:assert/strict';
import { staffAccounts, staffEmail, digest } from '../src/staff_accounts.js';
import { AccessError } from '../src/authorization.js';

function fixture() {
  const records = new Map();
  let revision = 0;
  let time = Date.parse('2026-11-11T12:00:00Z');
  const write = (path, data) => records.set(path, { data: structuredClone(data), version: String(++revision) });
  const owner = { uid: 'owner', role: 'owner', tenant_id: 'gym', status: 'active' };
  write('users/owner', owner);
  write('users/personal', { email: 'ana@example.test', role: 'owner', tenant_id: 'other', status: 'active' });
  write('tenants/gym', { name: 'Gimnasio Céntrico' });
  write('tenants/gym/branches/b', { name: 'Centro' });
  const messages = [];
  const accounts = new Map();
  let deliveryWorks = true;
  let loseCommitResponse = false;
  const service = staffAccounts({
    now: () => time, appUrl: 'https://app.example.test/',
    store: {
      read: async path => structuredClone(records.get(path) ?? null),
      async commit(writes) {
        for (const item of writes) {
          if ((records.get(item.path)?.version ?? null) !== item.version) throw new AccessError('Conflict', 409);
        }
        for (const item of writes) write(item.path, item.data);
        if (loseCommitResponse) {
          loseCommitResponse = false;
          throw new AccessError('Commit response lost', 503);
        }
      },
    },
    auth: {
      async create(email) { const uid = `work-${accounts.size + 1}`; accounts.set(email, uid); return uid; },
      async remove(uid) { for (const [email, id] of accounts) if (id === uid) accounts.delete(email); },
      async resetLink(email) { assert.ok(accounts.has(email)); return 'https://firebase.test/action?oobCode=one-use-code'; },
      lookup: async email => accounts.get(email) ?? null,
    },
    async sendEmail(to, subject, html) { messages.push({ to, subject, html }); return deliveryWorks; },
  });
  const body = { name: 'Ana López', email: 'Ana@example.test', tenant_id: 'gym', branch_id: 'b', role: 'receptionist', gymName: 'Forged gym' };
  function link() {
    const url = new URL(messages.at(-1).html.match(/href="([^"]+)"/)[1].replaceAll('&amp;', '&'));
    return new URLSearchParams(url.hash.split('?')[1]);
  }
  return { service, records, accounts, messages, owner, body, write, link,
    data: path => records.get(path)?.data,
    advance: ms => { time += ms; }, failEmail: () => { deliveryWorks = false; }, restoreEmail: () => { deliveryWorks = true; },
    loseCommitResponse: () => { loseCommitResponse = true; } };
}
const rejects = (operation, status) => assert.rejects(operation, error => error.status === status);

test('generated work identity is pending and keeps an existing personal account untouched', async () => {
  const f = fixture();
  const personal = structuredClone(f.data('users/personal'));
  const created = await f.service.create(f.owner, f.body);
  assert.match(created.username, /^gimnasiocentrico\.ana\.[a-f0-9]{12}$/);
  assert.equal(created.email_sent, true);
  const profile = f.data(`users/${created.uid}`);
  assert.equal(profile.status, 'pending');
  assert.equal(profile.email, 'ana@example.test');
  assert.equal(Object.values(profile.permissions).some(Boolean), false);
  assert.equal(f.accounts.get(staffEmail(created.username)), created.uid);
  assert.deepEqual(f.data('users/personal'), personal);
  assert.equal(f.messages[0].to, 'ana@example.test');
  assert.ok(f.messages[0].subject.includes('Gimnasio Céntrico'));
  const token = f.link().get('token');
  assert.equal(f.data(`staff_invitations/${created.uid}`).token_hash, await digest(token));
  assert.equal(JSON.stringify([...f.records.values()]).includes(token), false);
  assert.equal(JSON.stringify(created).includes(token), false);
  await rejects(() => f.service.create(f.owner, f.body), 409);
  assert.equal(f.accounts.size, 1);
});

test('role and tenant restrictions apply inside account creation', async () => {
  const f = fixture();
  const staff = { ...f.owner, uid: 'staff', role: 'staff' };
  for (const role of ['owner', 'superuser', 'staff']) await rejects(() => f.service.create(staff, { ...f.body, role }), 403);
  await rejects(() => f.service.create({ ...f.owner, tenant_id: 'other' }, f.body), 403);
  await rejects(() => f.service.create(f.owner, { ...f.body, branch_id: 'missing' }), 409);
  assert.equal(f.accounts.size, 0);
  await f.service.create(staff, f.body);
});

test('duplicate concurrent invitations reserve only one account and roll back the losing Auth identity', async () => {
  const f = fixture();
  const results = await Promise.allSettled([f.service.create(f.owner, f.body), f.service.create(f.owner, f.body)]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(f.accounts.size, 1);
  assert.equal(f.messages.length, 1);
});

test('a lost successful creation response never deletes the committed Auth account', async () => {
  const f = fixture();
  f.loseCommitResponse();
  const created = await f.service.create(f.owner, f.body);
  assert.equal(created.email_sent, true);
  assert.equal(f.accounts.get(staffEmail(created.username)), created.uid);
  assert.equal(f.data(`users/${created.uid}`).status, 'pending');
  await f.service.preview(created.uid, f.link().get('token'));
});

test('preview rejects tampered, expired or already processed links', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const token = f.link().get('token');
  assert.equal((await f.service.preview(created.uid, token)).branch_name, 'Centro');
  await rejects(() => f.service.preview(created.uid, '0'.repeat(64)), 404);
  f.advance(8 * 24 * 60 * 60 * 1000);
  await rejects(() => f.service.preview(created.uid, token), 410);
});

test('acceptance requires the exact recipient; it activates only once', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const token = f.link().get('token');
  await rejects(() => f.service.respond(created.uid, token, 'accept', f.owner), 403);
  await rejects(() => f.service.respond(created.uid, token, 'accept'), 403);
  await f.service.respond(created.uid, token, 'accept', { uid: created.uid });
  assert.equal(f.data(`users/${created.uid}`).status, 'active');
  assert.ok(f.data(`users/${created.uid}`).contact_verified_at);
  const acceptedVersion = f.records.get(`users/${created.uid}`).version;
  await f.service.respond(created.uid, token, 'accept', { uid: created.uid });
  assert.equal(f.records.get(`users/${created.uid}`).version, acceptedVersion);
  await rejects(() => f.service.preview(created.uid, token), 409);
});

test('acceptance rechecks the branch and current inviter authority', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const token = f.link().get('token');
  f.records.delete('tenants/gym/branches/b');
  await rejects(() => f.service.respond(created.uid, token, 'accept', { uid: created.uid }), 409);
  f.write('tenants/gym/branches/b', { name: 'Restored' });
  f.write('users/owner', { ...f.owner, status: 'suspended' });
  await rejects(() => f.service.respond(created.uid, token, 'accept', { uid: created.uid }), 409);
  assert.equal(f.data(`users/${created.uid}`).status, 'pending');
});

test('concurrent accept/reject consumes the invitation atomically', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const token = f.link().get('token');
  const results = await Promise.allSettled([
    f.service.respond(created.uid, token, 'accept', { uid: created.uid }),
    f.service.respond(created.uid, token, 'reject'),
  ]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  const accepted = f.data(`staff_invitations/${created.uid}`).status === 'accepted';
  assert.equal(f.data(`users/${created.uid}`).status, accepted ? 'active' : 'pending');
});

test('rejection and cancellation preserve identity and deny access; resend invalidates the old link', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const oldToken = f.link().get('token');
  await f.service.respond(created.uid, oldToken, 'reject');
  assert.equal(f.data(`users/${created.uid}`).invitation_status, 'rejected');
  assert.equal(f.data(`users/${created.uid}`).status, 'pending');
  await rejects(() => f.service.resend(f.owner, created.uid), 429);
  f.advance(61_000);
  await f.service.resend(f.owner, created.uid);
  await rejects(() => f.service.preview(created.uid, oldToken), 404);
  const newToken = f.link().get('token');
  await f.service.deactivate(f.owner, created.uid);
  await rejects(() => f.service.respond(created.uid, newToken, 'accept', { uid: created.uid }), 409);
  assert.equal(f.data(`users/${created.uid}`).invitation_status, 'cancelled');
  assert.equal(f.accounts.size, 1);
});

test('failed mail delivery leaves a recoverable pending account, never a duplicate', async () => {
  const f = fixture();
  f.failEmail();
  const created = await f.service.create(f.owner, f.body);
  assert.equal(created.email_sent, false);
  assert.equal(f.data(`users/${created.uid}`).status, 'pending');
  f.advance(61_000); f.restoreEmail();
  assert.equal((await f.service.resend(f.owner, created.uid)).email_sent, true);
  assert.equal(f.accounts.size, 1);
});

test('recovery delivers to verified contact only, is throttled and does not disclose existence', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const generic = { ok: true };
  assert.deepEqual(await f.service.recover(created.username, 'pending-ip'), generic);
  assert.equal(f.messages.length, 1);
  await f.service.respond(created.uid, f.link().get('token'), 'accept', { uid: created.uid });
  assert.deepEqual(await f.service.recover('not.a.user', 'unknown-ip'), generic);
  assert.deepEqual(await f.service.recover(created.username, 'active-ip'), generic);
  assert.equal(f.messages.length, 2);
  assert.equal(f.messages.at(-1).to, 'ana@example.test');
  assert.ok(f.messages.at(-1).html.includes('/staff-reset-password'));
  assert.deepEqual(await f.service.recover(created.username, 'other-ip'), generic);
  assert.equal(f.messages.length, 2);
  await f.service.deactivate(f.owner, created.uid);
  f.advance(61_000);
  await f.service.recover(created.username, 'active-ip');
  assert.equal(f.messages.length, 2);
  assert.equal(f.data(`users/${created.uid}`).status, 'suspended');
  assert.equal(f.accounts.size, 1);
  assert.equal(f.data('users/personal').status, 'active');
});

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
  let failCommit = false;
  let nextUid = 0;
  const resetRequests = [];
  const service = staffAccounts({
    now: () => time, appUrl: 'https://app.example.test/',
    store: {
      read: async path => structuredClone(records.get(path) ?? null),
      async commit(writes) {
        if (failCommit) { failCommit = false; throw new AccessError('Write unavailable', 503); }
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
      async create(email) {
        if (accounts.has(email)) throw new Error('EMAIL_EXISTS');
        const uid = `work-${++nextUid}`; accounts.set(email, uid); return uid;
      },
      async emailForUid(uid) { return [...accounts].find(([, id]) => id === uid)?.[0] ?? null; },
      async rename(uid, email) {
        if (accounts.has(email) && accounts.get(email) !== uid) throw new Error('EMAIL_EXISTS');
        for (const [oldEmail, id] of accounts) if (id === uid) accounts.delete(oldEmail);
        accounts.set(email, uid);
      },
      async requestReset(email) { resetRequests.push(email); },
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
  return { service, records, accounts, messages, resetRequests, owner, body, write, link,
    data: path => records.get(path)?.data,
    advance: ms => { time += ms; }, failEmail: () => { deliveryWorks = false; }, restoreEmail: () => { deliveryWorks = true; },
    loseCommitResponse: () => { loseCommitResponse = true; }, failCommit: () => { failCommit = true; } };
}
const rejects = (operation, status) => assert.rejects(operation, error => error.status === status);

test('generated work identity is pending and keeps an existing personal account untouched', async () => {
  const f = fixture();
  const personal = structuredClone(f.data('users/personal'));
  const created = await f.service.create(f.owner, f.body);
  assert.equal(created.username, 'gimnasiocentricoanalopez@omnigym.xyz');
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

test('work emails combine tenant and full staff names, normalize accents and resolve global collisions with a number', async () => {
  const f = fixture();
  f.accounts.set('gimnasiocentricoanalopez@omnigym.xyz', 'existing-account');
  const created = await f.service.create(f.owner, f.body);
  assert.equal(created.username, 'gimnasiocentricoanalopez2@omnigym.xyz');
  assert.equal(f.accounts.get('gimnasiocentricoanalopez@omnigym.xyz'), 'existing-account');
  assert.equal(f.accounts.get(created.username), created.uid);
  assert.ok(f.messages[0].html.includes(created.username));
});

test('long names still generate a valid email local part', async () => {
  const f = fixture();
  f.write('tenants/gym', { name: 'G'.repeat(100) });
  const created = await f.service.create(f.owner, { ...f.body, name: 'Á'.repeat(100) });
  assert.ok(created.username.split('@')[0].length <= 64);
  assert.match(created.username, /^[a-z0-9]+@omnigym\.xyz$/);
});

test('resending an old pending invitation upgrades the email without replacing UID or contact', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  const oldToken = f.link().get('token');
  const oldUsername = 'gym.ana.legacy';
  f.accounts.delete(created.username);
  f.accounts.set(staffEmail(oldUsername), created.uid);
  f.write(`users/${created.uid}`, { ...f.data(`users/${created.uid}`), username: oldUsername });
  f.advance(61_000);
  f.loseCommitResponse();
  const resent = await f.service.resend(f.owner, created.uid);
  assert.equal(resent.username, 'gimnasiocentricoanalopez@omnigym.xyz');
  assert.equal(f.accounts.get(resent.username), created.uid);
  assert.equal(f.accounts.has(staffEmail(oldUsername)), false);
  assert.equal(f.accounts.size, 1);
  assert.equal(f.data(`users/${created.uid}`).email, 'ana@example.test');
  assert.equal(f.data(`users/${created.uid}`).username, resent.username);
  assert.equal(f.messages.at(-1).to, 'ana@example.test');
  await rejects(() => f.service.preview(created.uid, oldToken), 404);
});

test('a failed profile write after renaming a pending account can be resumed safely', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  f.accounts.delete(created.username);
  f.accounts.set(staffEmail('gym.ana.legacy'), created.uid);
  f.write(`users/${created.uid}`, { ...f.data(`users/${created.uid}`), username: 'gym.ana.legacy' });
  f.advance(61_000); f.failCommit();
  await rejects(() => f.service.resend(f.owner, created.uid), 503);
  assert.equal(f.accounts.get(created.username), created.uid);
  assert.equal(f.data(`users/${created.uid}`).username, 'gym.ana.legacy');
  const resent = await f.service.resend(f.owner, created.uid);
  assert.equal(resent.username, created.username);
  assert.equal(f.data(`users/${created.uid}`).username, created.username);
  assert.equal(f.accounts.size, 1);
});

test('accepted legacy accounts retain their login and contact-based recovery', async () => {
  const f = fixture();
  const created = await f.service.create(f.owner, f.body);
  await f.service.respond(created.uid, f.link().get('token'), 'accept', { uid: created.uid });
  f.accounts.delete(created.username);
  f.accounts.set(staffEmail('gym.ana.legacy'), created.uid);
  f.write(`users/${created.uid}`, { ...f.data(`users/${created.uid}`), username: 'gym.ana.legacy' });
  await rejects(() => f.service.resend(f.owner, created.uid), 409);
  await f.service.recover('gym.ana.legacy', 'legacy-ip');
  assert.equal(f.messages.at(-1).to, 'ana@example.test');
  assert.equal(f.accounts.get(staffEmail('gym.ana.legacy')), created.uid);
});

test('personal Owner accounts on the corporate domain keep their original email recovery', async () => {
  const f = fixture();
  f.accounts.set('owner@omnigym.xyz', 'owner');
  await f.service.recover('OWNER@OMNIGYM.XYZ', 'owner-ip');
  assert.deepEqual(f.resetRequests, ['owner@omnigym.xyz']);
  assert.equal(f.messages.length, 0);
});

test('existing member accounts without a global operator profile keep corporate email recovery', async () => {
  const f = fixture();
  f.accounts.set('member@omnigym.xyz', 'member');
  await f.service.recover('member@omnigym.xyz', 'member-ip');
  assert.deepEqual(f.resetRequests, ['member@omnigym.xyz']);
  assert.equal(f.messages.length, 0);
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

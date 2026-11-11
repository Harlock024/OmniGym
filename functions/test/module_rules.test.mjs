import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, collection, getDocs, query, where } from 'firebase/firestore';

const host = process.env.FIRESTORE_EMULATOR_HOST;
assert.match(host ?? '', /^(127\.0\.0\.1|localhost):\d+$/, 'Tests must use the local emulator.');
const modules = ['dashboard', 'branches', 'members', 'scanner', 'memberships', 'billing', 'reports'];
const permissions = (...enabled) => Object.fromEntries(modules.map(key => [key, enabled.includes(key)]));
let env;
const db = uid => env.authenticatedContext(uid, { role: 'owner', tenant_id: 'gym' }).firestore();

before(async () => {
  const [hostname, port] = host.split(':');
  env = await initializeTestEnvironment({ projectId: 'demo-omnigym-roles', firestore: {
    host: hostname, port: Number(port), rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  } });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const firestore = context.firestore();
    const profile = (role, tenant = 'gym', grants = permissions()) => ({ role, tenant_id: tenant, status: 'active', name: role, permissions: grants });
    const data = {
      'tenants/gym': { owner_uid: 'owner', settings: {} },
      'users/owner': profile('owner'),
      'users/staff': profile('staff', 'gym', permissions('members', 'scanner')),
      'users/staff2': profile('staff'),
      'users/reception': profile('receptionist'),
      'users/other': profile('receptionist', 'other'),
      'users/billing': profile('receptionist', 'gym', permissions('billing')),
      'users/payments': profile('receptionist', 'gym', permissions('memberships')),
      'users/suspended': { ...profile('receptionist', 'gym', permissions('members')), status: 'suspended' },
      'tenants/gym/members/member': { uid: 'member', tenant_id: 'gym', name: 'Socio', expiration_date: new Date(), allowed_branches: ['b'] },
      'tenants/gym/branches/b': { name: 'Branch' },
      'tenants/gym/facturas/i': { tenant_id: 'gym' },
      'tenants/gym/payments/p': { member_id: 'member' },
    };
    for (const [path, value] of Object.entries(data)) await setDoc(doc(firestore, path), value);
  });
});
after(async () => { await env?.cleanup(); });

test('stale Owner claims do not give a receptionist module access', async () => {
  await assertFails(getDoc(doc(db('reception'), 'tenants/gym/members/member')));
  await assertFails(getDoc(doc(db('reception'), 'tenants/gym/facturas/i')));
  await assertFails(setDoc(doc(db('reception'), 'tenants/gym/branches/new'), { name: 'Forbidden' }));
  await assertSucceeds(getDoc(doc(db('reception'), 'users/reception')));
});
test('Owner can assign modules; access can be granted and revoked without new claims', async () => {
  await assertSucceeds(updateDoc(doc(db('owner'), 'users/reception'), { permissions: permissions('members') }));
  await assertSucceeds(getDoc(doc(db('reception'), 'tenants/gym/members/member')));
  await assertSucceeds(updateDoc(doc(db('owner'), 'users/reception'), { permissions: permissions() }));
  await assertFails(getDoc(doc(db('reception'), 'tenants/gym/members/member')));
});
test('Staff can grant only its own modules and only to receptionists of its gym', async () => {
  await assertSucceeds(updateDoc(doc(db('staff'), 'users/reception'), { permissions: permissions('scanner') }));
  await assertFails(updateDoc(doc(db('staff'), 'users/reception'), { permissions: permissions('billing') }));
  await assertFails(updateDoc(doc(db('staff'), 'users/staff2'), { permissions: permissions('scanner') }));
  await assertFails(updateDoc(doc(db('staff'), 'users/other'), { permissions: permissions('scanner') }));
  await assertFails(updateDoc(doc(db('staff'), 'users/owner'), { permissions: permissions('scanner') }));
  await assertFails(updateDoc(doc(db('staff'), 'users/staff'), { permissions: permissions('billing') }));
  await assertSucceeds(updateDoc(doc(db('owner'), 'users/reception'), { permissions: permissions() }));
});
test('profiles cannot self-promote or forge permission keys', async () => {
  await assertFails(updateDoc(doc(db('reception'), 'users/reception'), { role: 'owner' }));
  await assertFails(updateDoc(doc(db('owner'), 'users/reception'), { role: 'owner' }));
  await assertFails(updateDoc(doc(db('owner'), 'users/reception'), { permissions: { superuser: true } }));
  await assertFails(updateDoc(doc(db('owner'), 'users/reception'), { permissions: { members: 'true' } }));
  await assertSucceeds(updateDoc(doc(db('reception'), 'users/reception'), { name: 'Perfil actualizado' }));
});
test('Staff with every grant can save the complete checkbox map', async () => {
  await assertSucceeds(updateDoc(doc(db('owner'), 'users/staff2'), { permissions: permissions(...modules) }));
  await assertSucceeds(updateDoc(doc(db('staff2'), 'users/reception'), { permissions: permissions(...modules) }));
  await assertSucceeds(updateDoc(doc(db('owner'), 'users/reception'), { permissions: permissions() }));
});
test('billing and payments grants enable their complete modules but not other writes', async () => {
  await assertSucceeds(getDoc(doc(db('billing'), 'tenants/gym/facturas/i')));
  await assertFails(updateDoc(doc(db('billing'), 'tenants/gym/members/member'), { name: 'Forbidden' }));
  await assertSucceeds(setDoc(doc(db('payments'), 'tenants/gym/payments/new'), { member_id: 'member' }));
  await assertSucceeds(updateDoc(doc(db('payments'), 'tenants/gym/members/member'), { expiration_date: new Date() }));
  await assertFails(updateDoc(doc(db('payments'), 'tenants/gym/members/member'), { name: 'Forbidden' }));
  await assertFails(getDoc(doc(db('suspended'), 'tenants/gym/members/member')));
});
test('team queries and existing member portal still work', async () => {
  await assertSucceeds(getDocs(query(collection(db('staff'), 'users'), where('tenant_id', '==', 'gym'))));
  await assertSucceeds(getDoc(doc(db('member'), 'tenants/gym/members/member')));
  await assertSucceeds(getDoc(doc(db('member'), 'tenants/gym')));
});
test('new gym ownership cannot be claimed by another account', async () => {
  await assertSucceeds(setDoc(doc(db('new-owner'), 'tenants/new-gym'), { owner_uid: 'new-owner', settings: {} }));
  await assertSucceeds(setDoc(doc(db('new-owner'), 'users/new-owner'), { role: 'owner', tenant_id: 'new-gym', status: 'active' }));
  await assertFails(setDoc(doc(db('attacker'), 'users/attacker'), { role: 'owner', tenant_id: 'gym', status: 'active' }));
  await assertFails(updateDoc(doc(db('owner'), 'tenants/gym'), { owner_uid: 'reception' }));
});

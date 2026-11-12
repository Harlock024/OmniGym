import { AccessError } from './authorization.js';
import { initialPermissions, canManageUser } from './module_access.js';

// Work logins have no mailbox; delivery always uses the contact address.
// Keep the legacy domain for accounts created before the work-email format.
export const STAFF_AUTH_DOMAIN = 'staff.omnigym.invalid';
export const WORK_EMAIL_DOMAIN = 'omnigym.xyz';
const INVITATION_LIFETIME = 7 * 24 * 60 * 60 * 1000;
const fail = (message, status = 400) => { throw new AccessError(message, status); };
const slug = (value, fallback) => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 30) || fallback;
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const randomSecret = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
export const staffEmail = username => username.includes('@') ? username : `${username}@${STAFF_AUTH_DOMAIN}`;
const isWorkEmail = value => /^[a-z0-9][a-z0-9._-]{0,63}@omnigym\.xyz$/.test(value);
const isLegacyEmail = value => /^[a-z0-9][a-z0-9._-]{2,79}@staff\.omnigym\.invalid$/.test(value);
const emailExists = error => /EMAIL_EXISTS|email-already-exists/.test(error.message ?? '');
export async function digest(value) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))), b => b.toString(16).padStart(2, '0')).join('');
}

// store.read -> { data, version }; commit atomically checks versions (null = absent).
// No invitation secret or password is persisted or returned to the inviter.
export function staffAccounts({ store, auth, sendEmail, appUrl, now = () => Date.now() }) {
  async function assignWorkEmail(gymName, name, uid) {
    // Preserve UID and history when upgrading an unaccepted legacy invitation.
    if (uid) {
      const current = await auth.emailForUid(uid);
      if (isWorkEmail(current ?? '')) return { uid, username: current };
    }
    const base = `${slug(gymName, 'gimnasio')}${slug(name, 'empleado')}`;
    for (let attempt = 1; attempt <= 20; attempt++) {
      const username = `${base}${attempt === 1 ? '' : attempt}@${WORK_EMAIL_DOMAIN}`;
      try {
        let accountUid = uid;
        if (uid) await auth.rename(uid, username);
        else accountUid = await auth.create(username, name);
        return { uid: accountUid, username };
      } catch (error) {
        if (!emailExists(error)) throw error;
      }
    }
    fail('No se pudo asignar un correo laboral disponible. Usa un nombre más específico.', 409);
  }
  function actionUrl(path, params) {
    const url = new URL(appUrl);
    if (url.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(url.hostname)) fail('APP_BASE_URL requiere HTTPS.', 503);
    url.hash = `${path}?${new URLSearchParams(params)}`;
    return url.toString();
  }
  async function sendInvitation(profile, gym, secret) {
    const resetLink = await auth.resetLink(staffEmail(profile.username));
    const code = new URL(resetLink).searchParams.get('oobCode');
    if (!code) fail('No se pudo generar la activación.', 503);
    const link = actionUrl('/staff-invitation', { id: profile.id, token: secret, oobCode: code });
    return sendEmail(profile.email, `Invitación a ${gym.name} — OmniGym`,
      `<h2>Hola, ${escapeHtml(profile.name)}</h2><p>Te invitaron a trabajar en <strong>${escapeHtml(gym.name)}</strong>.</p>
       <p>Tu correo de acceso laboral es <strong>${escapeHtml(profile.username)}</strong>.</p>
       <p><a href="${escapeHtml(link)}">Revisar invitación</a></p>
       <p>Abre la invitación para ver el gimnasio, la sucursal y tu rol. Podrás aceptar o rechazar; si aceptas, configurarás tu contraseña.</p>
       <p>La invitación vence en 7 días; el enlace de contraseña puede vencer antes. Si ocurre, solicita un reenvío al gimnasio. Las comunicaciones y la recuperación llegarán a este correo de contacto.</p>`);
  }
  async function invitation(id, secret, allowAccepted = false) {
    if (!/^[a-zA-Z0-9_-]{1,128}$/.test(id ?? '') || !/^[a-f0-9]{64}$/.test(secret ?? '')) fail('La invitación no es válida.', 404);
    const record = await store.read(`staff_invitations/${id}`);
    if (!record || record.data.token_hash !== await digest(secret)) fail('La invitación no es válida.', 404);
    // A lost HTTP response can be retried by the same authenticated recipient.
    // This never performs the activation transition a second time.
    if (allowAccepted && record.data.status === 'accepted') return record;
    if (record.data.status !== 'pending') fail('Esta invitación ya fue atendida o cancelada.', 409);
    if (Date.parse(record.data.expires_at) <= now()) fail('La invitación venció. Solicita un reenvío al gimnasio.', 410);
    return record;
  }
  async function validateAssignment(profile) {
    const gym = await store.read(`tenants/${profile.tenant_id}`);
    const branch = await store.read(`tenants/${profile.tenant_id}/branches/${profile.branch_id}`);
    if (!gym || !branch) fail('El gimnasio o la sucursal ya no están disponibles.', 409);
    return { gym: gym.data, branch: branch.data };
  }
  return {
    async create(actor, body) {
      const name = typeof body.name === 'string' ? body.name.trim() : '';
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
      if (!name || name.length > 120 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || email.endsWith(`@${STAFF_AUTH_DOMAIN}`)) fail('Indica un nombre y correo de contacto válidos.');
      const target = { role: body.role, tenant_id: body.tenant_id };
      if (!['staff', 'receptionist'].includes(body.role) || !canManageUser(actor, target)) fail('No puedes asignar ese rol.', 403);
      const { gym } = await validateAssignment({ ...target, branch_id: body.branch_id });
      const accountKey = `staff_account_keys/${await digest(`${body.tenant_id}\0${email}`)}`;
      if (await store.read(accountKey)) fail('Ya existe una cuenta laboral para ese contacto en este gimnasio. Adminístrala desde Equipo.', 409);
      const { uid, username } = await assignWorkEmail(gym.name, name);
      const secret = randomSecret();
      const createdAt = new Date(now()).toISOString();
      const profile = {
        name, email, username, account_type: 'managed_staff', role: body.role,
        tenant_id: body.tenant_id, branch_id: body.branch_id, permissions: initialPermissions(body.role),
        status: 'pending', invitation_status: 'pending', contact_verified_at: null,
        csd_cargo: typeof body.csd_cargo === 'string' ? body.csd_cargo.slice(0, 120) : null,
        created_at: new Date(createdAt),
      };
      try {
        await store.commit([
          { path: accountKey, data: { uid }, version: null },
          { path: `users/${uid}`, data: profile, version: null },
          { path: `staff_invitations/${uid}`, data: { token_hash: await digest(secret), status: 'pending', created_by: actor.uid,
            expires_at: new Date(now() + INVITATION_LIFETIME).toISOString(), created_at: createdAt }, version: null },
        ]);
      } catch (error) {
        // A timeout can happen after Firestore committed. Never delete a valid
        // identity just because its successful commit response was lost.
        let reservation;
        try { reservation = await store.read(accountKey); } catch { /* Unknown outcome: leave Auth intact. */ }
        if (reservation?.data.uid !== uid) {
          if (error.status === 409 || reservation) await auth.remove(uid);
          throw error;
        }
      }
      let emailSent = false;
      try { emailSent = await sendInvitation({ ...profile, id: uid }, gym, secret); }
      catch { /* Account remains pending; inviter can resend without duplicating it. */ }
      return { uid, username, email_sent: emailSent };
    },
    async preview(id, secret) {
      await invitation(id, secret);
      const profile = (await store.read(`users/${id}`))?.data;
      if (!profile || profile.status !== 'pending') fail('La cuenta ya no está disponible.', 409);
      const { gym, branch } = await validateAssignment(profile);
      return { name: profile.name, username: profile.username, gym_name: gym.name, branch_name: branch.name, role: profile.role };
    },
    async respond(id, secret, decision, actor) {
      if (!['accept', 'reject'].includes(decision)) fail('Respuesta inválida.');
      const invite = await invitation(id, secret, decision === 'accept' && actor?.uid === id);
      if (invite.data.status === 'accepted') return { ok: true };
      const profile = await store.read(`users/${id}`);
      if (!profile || profile.data.status !== 'pending') fail('La cuenta ya no está pendiente.', 409);
      if (decision === 'accept') {
        if (actor?.uid !== id) fail('Inicia sesión con la cuenta de esta invitación.', 403);
        await validateAssignment(profile.data);
        const inviter = (await store.read(`users/${invite.data.created_by}`))?.data;
        if (!inviter || inviter.status !== 'active' || !canManageUser({ ...inviter, uid: invite.data.created_by }, { ...profile.data, id })) fail('La persona que te invitó ya no puede asignar este acceso. Solicita un reenvío al gimnasio.', 409);
      }
      const timestamp = new Date(now()).toISOString();
      await store.commit([
        { path: `staff_invitations/${id}`, data: { ...invite.data, status: decision === 'accept' ? 'accepted' : 'rejected', responded_at: timestamp }, version: invite.version },
        { path: `users/${id}`, data: { ...profile.data, invitation_status: decision === 'accept' ? 'accepted' : 'rejected',
          status: decision === 'accept' ? 'active' : 'pending', ...(decision === 'accept' ? { contact_verified_at: timestamp } : {}) }, version: profile.version },
      ]);
      return { ok: true };
    },
    async resend(actor, uid) {
      if (!/^[a-zA-Z0-9_-]{1,128}$/.test(uid ?? '')) fail('Cuenta inválida.');
      const profile = await store.read(`users/${uid}`);
      if (!profile || !canManageUser(actor, { ...profile.data, id: uid })) fail('No puedes administrar esta cuenta.', 403);
      if (profile.data.account_type !== 'managed_staff' || profile.data.status !== 'pending') fail('Esta cuenta ya no requiere activación.', 409);
      const invite = await store.read(`staff_invitations/${uid}`);
      if (invite && now() - Date.parse(invite.data.created_at) < 60_000) fail('Espera un minuto antes de reenviar.', 429);
      const { gym } = await validateAssignment(profile.data);
      const identity = isWorkEmail(profile.data.username ?? '')
        ? { username: profile.data.username }
        : await assignWorkEmail(gym.name, profile.data.name, uid);
      const secret = randomSecret();
      const tokenHash = await digest(secret);
      try {
        await store.commit([
          { path: `staff_invitations/${uid}`, data: { token_hash: tokenHash, status: 'pending', created_by: actor.uid,
            expires_at: new Date(now() + INVITATION_LIFETIME).toISOString(), created_at: new Date(now()).toISOString() }, version: invite?.version ?? null },
          { path: `users/${uid}`, data: { ...profile.data, username: identity.username, invitation_status: 'pending' }, version: profile.version },
        ]);
      } catch (error) {
        // Retry a committed write whose response was lost, without rotating Auth
        // back to an address another concurrent request may already be using.
        const saved = await store.read(`staff_invitations/${uid}`);
        if (saved?.data.token_hash !== tokenHash) throw error;
      }
      let emailSent = false;
      try { emailSent = await sendInvitation({ ...profile.data, username: identity.username, id: uid }, gym, secret); } catch { /* Resend remains available. */ }
      return { username: identity.username, email_sent: emailSent };
    },
    async deactivate(actor, uid) {
      if (!/^[a-zA-Z0-9_-]{1,128}$/.test(uid ?? '')) fail('Cuenta inválida.');
      const profile = await store.read(`users/${uid}`);
      if (!profile || !canManageUser(actor, { ...profile.data, id: uid })) fail('No puedes administrar esta cuenta.', 403);
      const invite = await store.read(`staff_invitations/${uid}`);
      const pending = profile.data.status === 'pending';
      await store.commit([
        { path: `users/${uid}`, data: { ...profile.data, status: pending ? 'pending' : 'suspended', ...(pending ? { invitation_status: 'cancelled' } : {}) }, version: profile.version },
        ...(invite && invite.data.status === 'pending' ? [{ path: `staff_invitations/${uid}`, data: { ...invite.data, status: 'cancelled' }, version: invite.version }] : []),
      ]);
      return { ok: true };
    },
    async recover(username, ip) {
      // Generic replies and persisted cooldowns prevent account enumeration and mail floods.
      const result = { ok: true };
      if (typeof username !== 'string') return result;
      username = username.trim().toLowerCase();
      if (!/^[a-z0-9][a-z0-9._-]{2,79}$/.test(username) && !isWorkEmail(username) && !isLegacyEmail(username)) return result;
      const limitPath = `staff_recovery_limits/${await digest(ip || 'unknown')}`;
      const limit = await store.read(limitPath);
      if (limit && now() - limit.data.at < 30_000) return result;
      try { await store.commit([{ path: limitPath, data: { at: now() }, version: limit?.version ?? null }]); }
      catch (error) { if (error.status === 409) return result; throw error; }
      const account = await auth.lookup(staffEmail(username));
      if (!account) return result;
      const profile = await store.read(`users/${account}`);
      if (!profile || profile.data.status !== 'active') return result;
      const managed = profile.data.account_type === 'managed_staff';
      if ((managed && !profile.data.contact_verified_at) || (!managed && !isWorkEmail(username))) return result;
      const throttlePath = `staff_recovery_accounts/${account}`;
      const throttle = await store.read(throttlePath);
      if (throttle && now() - throttle.data.at < 60_000) return result;
      try { await store.commit([{ path: throttlePath, data: { at: now() }, version: throttle?.version ?? null }]); }
      catch (error) { if (error.status === 409) return result; throw error; }
      // Existing personal/Owner accounts at the same domain retain Firebase's
      // normal recovery flow; managed accounts always recover to their contact.
      if (!managed) { await auth.requestReset(username); return result; }
      const resetLink = await auth.resetLink(staffEmail(username));
      const code = new URL(resetLink).searchParams.get('oobCode');
      if (!code) fail('No se pudo generar la recuperación.', 503);
      const link = actionUrl('/staff-reset-password', { oobCode: code });
      if (!await sendEmail(profile.data.email, 'Recupera tu acceso laboral — OmniGym',
        `<p>Solicitaste recuperar el acceso de <strong>${escapeHtml(username)}</strong>.</p><p><a href="${escapeHtml(link)}">Establecer una nueva contraseña</a></p><p>Si no lo solicitaste, puedes ignorar este correo.</p>`)) fail('No se pudo enviar la recuperación. Intenta más tarde.', 503);
      return result;
    },
  };
}

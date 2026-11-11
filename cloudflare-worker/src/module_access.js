export const MODULES = ['dashboard', 'branches', 'members', 'scanner', 'memberships', 'billing', 'reports'];

export function hasModule(user, module) {
  if (!user || user.status !== 'active') return false;
  if (user.role === 'owner' || user.role === 'superuser') return true;
  if (!['staff', 'receptionist'].includes(user.role)) return false;
  const permissions = user.permissions ?? {};
  if (Object.hasOwn(permissions, module)) return permissions[module] === true;
  return user.role === 'staff' && Object.keys(permissions).length === 0 && ['dashboard', 'scanner'].includes(module);
}

export function initialPermissions(role) {
  return Object.fromEntries(MODULES.map(key => [key, role === 'staff' && ['dashboard', 'scanner'].includes(key)]));
}

export function canManageUser(actor, target) {
  if (!actor || actor.status !== 'active' || !target || actor.uid === target.id) return false;
  if (!['staff', 'receptionist'].includes(target.role)) return false;
  if (actor.role === 'superuser') return true;
  if (!actor.tenant_id || actor.tenant_id !== target.tenant_id) return false;
  return actor.role === 'owner' || (actor.role === 'staff' && target.role === 'receptionist');
}

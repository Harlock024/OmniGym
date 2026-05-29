import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_user.dart';
import '../../core/models/tenant.dart';
import '../../core/providers/providers.dart';

// ── Lista de todos los tenants (solo superuser) ──────────────────────────────

final allTenantsProvider = StreamProvider<List<Tenant>>((ref) {
  return ref.watch(tenantRepositoryProvider).watchAll();
});

// ── Lista de todos los usuarios (solo superuser) ─────────────────────────────

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(userRepositoryProvider).watchAll();
});

// ── Búsqueda en lista de tenants ─────────────────────────────────────────────

final tenantSearchProvider = StateProvider<String>((ref) => '');

final filteredTenantsProvider = Provider<AsyncValue<List<Tenant>>>((ref) {
  return ref.watch(allTenantsProvider).whenData((tenants) {
    final q = ref.watch(tenantSearchProvider).trim().toLowerCase();
    if (q.isEmpty) return tenants;
    return tenants.where((t) {
      return t.name.toLowerCase().contains(q) ||
          (t.settings.rfc?.toLowerCase().contains(q) ?? false) ||
          (t.settings.contactName?.toLowerCase().contains(q) ?? false);
    }).toList();
  });
});

// ── Búsqueda en lista de usuarios ────────────────────────────────────────────

final userSearchProvider = StateProvider<String>((ref) => '');

final filteredUsersProvider = Provider<AsyncValue<List<AppUser>>>((ref) {
  return ref.watch(allUsersProvider).whenData((users) {
    final q = ref.watch(userSearchProvider).trim().toLowerCase();
    if (q.isEmpty) return users;
    return users.where((u) {
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          (u.tenantId?.toLowerCase().contains(q) ?? false);
    }).toList();
  });
});

// ── Mapa de tenantId → Tenant (para lookups rápidos) ─────────────────────────

final tenantMapProvider = Provider<Map<String, Tenant>>((ref) {
  final tenantsAsync = ref.watch(allTenantsProvider);
  return tenantsAsync.valueOrNull?.fold<Map<String, Tenant>>(
        {},
        (map, t) => map..[t.id] = t,
      ) ??
      {};
});

// ── Módulos OmniGym disponibles para permisos ────────────────────────────────

const kOmniGymModules = [
  (key: 'dashboard', label: 'Dashboard'),
  (key: 'branches', label: 'Sucursales'),
  (key: 'members', label: 'Socios'),
  (key: 'scanner', label: 'Scanner QR'),
  (key: 'payments', label: 'Pagos'),
  (key: 'memberships', label: 'Membresías'),
  (key: 'staff', label: 'Staff'),
  (key: 'settings', label: 'Configuración'),
  (key: 'billing', label: 'Facturación SAT'),
];

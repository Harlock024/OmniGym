import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_user.dart';
import '../../core/providers/providers.dart';

// Stream de todos los operadores del tenant activo
final staffListProvider = StreamProvider<List<AppUser>>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  if (tenantId == null) {
    yield [];
    return;
  }
  yield* ref.watch(userRepositoryProvider).watchByTenant(tenantId);
});

// Mapa branchId -> nombre de sucursal del tenant activo (para la columna Sucursal)
final staffBranchNamesProvider = StreamProvider<Map<String, String>>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  if (tenantId == null) {
    yield <String, String>{};
    return;
  }
  yield* ref
      .watch(branchRepositoryProvider)
      .watchAll(tenantId)
      .map((branches) => {for (final b in branches) b.id: b.name});
});

// Filtro de rol seleccionado (null = todos)
final staffRoleFilterProvider = StateProvider<UserRole?>((ref) => null);

// Filtro de estado seleccionado (null = todos)
final staffStatusFilterProvider = StateProvider<UserStatus?>((ref) => null);

// Lista filtrada derivada
final filteredStaffProvider = Provider<AsyncValue<List<AppUser>>>((ref) {
  return ref.watch(staffListProvider).whenData((staff) {
    final roleFilter = ref.watch(staffRoleFilterProvider);
    final statusFilter = ref.watch(staffStatusFilterProvider);
    return staff.where((u) {
      if (roleFilter != null && u.role != roleFilter) return false;
      if (statusFilter != null && u.status != statusFilter) return false;
      return true;
    }).toList();
  });
});

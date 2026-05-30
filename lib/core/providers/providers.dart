import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/branch.dart';
import '../models/member.dart';
import '../models/membership_plan.dart';
import '../models/payment.dart';
import '../models/tenant.dart';
import '../repositories/branch_repository.dart';
import '../repositories/member_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/plan_repository.dart';
import '../repositories/tenant_repository.dart';
import '../repositories/user_repository.dart';
import '../services/kill_switch_service.dart';

// ─── Firebase instances ───────────────────────────────────────────────────────

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (_) => FirebaseStorage.instance,
);

// ─── Auth ────────────────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(authStateProvider).valueOrNull,
);

// ─── Repositories ─────────────────────────────────────────────────────────────

final tenantRepositoryProvider = Provider<TenantRepository>(
  (ref) => TenantRepository(ref.watch(firestoreProvider)),
);

final branchRepositoryProvider = Provider<BranchRepository>(
  (ref) => BranchRepository(ref.watch(firestoreProvider)),
);

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepository(ref.watch(firestoreProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(firestoreProvider)),
);

// ─── Services ────────────────────────────────────────────────────────────────

final killSwitchServiceProvider = Provider<KillSwitchService>(
  (_) => const KillSwitchService(),
);

// ─── Tenant activo (leído de custom claims del JWT) ──────────────────────────

final activeTenantIdProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  // El tenant_id viene en los custom claims del JWT
  // Se obtiene de forma asíncrona vía getIdTokenResult()
  return null; // ver activeTenantIdFutureProvider
});

final activeTenantIdFutureProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final result = await user.getIdTokenResult();
  final tenantId = result.claims?['tenant_id'] as String?;

  // Fallback: si onUserWritten no ha corrido, leer de Firestore
  if (tenantId == null) {
    final doc = await ref
        .read(firestoreProvider)
        .collection('users')
        .doc(user.uid)
        .get();
    return doc.data()?['tenant_id'] as String?;
  }

  return tenantId;
});

final activeTenantProvider = StreamProvider<Tenant?>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  if (tenantId == null) {
    yield null;
    return;
  }
  yield* ref.watch(tenantRepositoryProvider).watch(tenantId);
});

// ─── Rol del usuario actual ───────────────────────────────────────────────────

final currentUserRoleProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final result = await user.getIdTokenResult();
  final role = result.claims?['role'] as String?;

  if (role == null) {
    final doc = await ref
        .read(firestoreProvider)
        .collection('users')
        .doc(user.uid)
        .get();
    return doc.data()?['role'] as String?;
  }

  return role;
});

final currentBranchIdProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final result = await user.getIdTokenResult();
  return result.claims?['branch_id'] as String?;
});

// ─── Métricas por sucursal ───────────────────────────────────────────────────

final activeMemberCountProvider =
    StreamProvider.family<int, ({String tenantId, String branchId})>(
  (ref, args) => ref
      .watch(memberRepositoryProvider)
      .watchActiveCount(args.tenantId, args.branchId),
);

final todayCheckInCountProvider =
    StreamProvider.family<int, ({String tenantId, String branchId})>(
  (ref, args) => ref
      .watch(branchRepositoryProvider)
      .watchTodayCheckInCount(args.tenantId, args.branchId),
);

// ─── Dashboard — métricas tenant-wide ────────────────────────────────────────

final activeTenantMemberCountProvider =
    StreamProvider.family<int, String>((ref, tenantId) => ref
        .watch(memberRepositoryProvider)
        .watchActiveTenantCount(tenantId));

final expiringMemberCountProvider =
    StreamProvider.family<int, String>((ref, tenantId) => ref
        .watch(memberRepositoryProvider)
        .watchExpiringCount(tenantId));

final newMembersThisMonthProvider =
    StreamProvider.family<int, String>((ref, tenantId) => ref
        .watch(memberRepositoryProvider)
        .watchNewThisMonth(tenantId));

// ─── Dashboard — métricas por sucursal ───────────────────────────────────────

final dailyCheckInsProvider = StreamProvider.family<
    List<({DateTime day, int count})>,
    ({String tenantId, String branchId})>(
  (ref, args) => ref
      .watch(branchRepositoryProvider)
      .watchDailyCheckIns(args.tenantId, args.branchId),
);

final recentCheckInsProvider = StreamProvider.family<
    List<Map<String, dynamic>>,
    ({String tenantId, String branchId})>(
  (ref, args) => ref
      .watch(branchRepositoryProvider)
      .watchRecentCheckIns(args.tenantId, args.branchId),
);

// ─── AppUser del operador autenticado ────────────────────────────────────────

final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watch(user.uid);
});

// ─── Socios ───────────────────────────────────────────────────────────────────

final membersProvider = StreamProvider.family<List<Member>, String>(
  (ref, tenantId) =>
      ref.watch(memberRepositoryProvider).watchAll(tenantId),
);

// ─── Sucursales ───────────────────────────────────────────────────────────────

final branchesProvider = StreamProvider.family<List<Branch>, String>(
  (ref, tenantId) =>
      ref.watch(branchRepositoryProvider).watchAll(tenantId),
);

final branchProvider =
    StreamProvider.family<Branch?, ({String tenantId, String branchId})>(
  (ref, args) =>
      ref.watch(branchRepositoryProvider).watch(args.tenantId, args.branchId),
);

// ─── Planes de membresía ──────────────────────────────────────────────────────

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => PlanRepository(ref.watch(firestoreProvider)),
);

final activePlansProvider = StreamProvider.family<List<MembershipPlan>, String>(
  (ref, tenantId) =>
      ref.watch(planRepositoryProvider).watchActive(tenantId),
);

final allPlansProvider = StreamProvider.family<List<MembershipPlan>, String>(
  (ref, tenantId) =>
      ref.watch(planRepositoryProvider).watchAll(tenantId),
);

// ─── Pagos ────────────────────────────────────────────────────────────────────

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(firestoreProvider)),
);

final tenantPaymentsProvider = StreamProvider.family<List<Payment>, String>(
  (ref, tenantId) =>
      ref.watch(paymentRepositoryProvider).watchByTenant(tenantId),
);

final branchPaymentsProvider =
    StreamProvider.family<List<Payment>, ({String tenantId, String branchId})>(
  (ref, args) => ref
      .watch(paymentRepositoryProvider)
      .watchByBranch(args.tenantId, args.branchId),
);

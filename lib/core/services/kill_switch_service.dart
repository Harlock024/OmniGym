import '../errors/access_errors.dart';
import '../models/branch.dart';
import '../models/member.dart';
import '../models/tenant.dart';

class KillSwitchService {
  const KillSwitchService();

  /// Valida los 3 niveles de acceso en orden estricto:
  ///   Nivel 0 → Tenant activo
  ///   Nivel 1 → Sucursal activa
  ///   Nivel 2 → Membresía vigente + sucursal permitida
  ///
  /// Lanza [AccessError] en el primer nivel que falle.
  void validate({
    required Tenant tenant,
    required Branch branch,
    required Member member,
    required String targetBranchId,
  }) {
    _checkTenant(tenant);
    _checkBranch(branch);
    _checkMember(member, targetBranchId);
  }

  void _checkTenant(Tenant tenant) {
    if (tenant.subscriptionStatus != SubscriptionStatus.active) {
      throw const TenantSuspendedError();
    }
    // Cobro SaaS B2B: si el gimnasio tiene un pago pendiente con la plataforma,
    // se corta el acceso (kill switch) hasta que regularice.
    if (tenant.pastDue) {
      throw const TenantPastDueError();
    }
  }

  void _checkBranch(Branch branch) {
    if (!branch.isActive) {
      throw const BranchInactiveError();
    }
  }

  void _checkMember(Member member, String targetBranchId) {
    if (member.accessStatus == AccessStatus.suspended) {
      throw const MemberSuspendedError();
    }

    if (member.expirationDate.isBefore(DateTime.now())) {
      throw const MemberExpiredError();
    }

    if (!member.allowedBranches.contains(targetBranchId)) {
      throw const BranchNotAllowedError();
    }
  }
}

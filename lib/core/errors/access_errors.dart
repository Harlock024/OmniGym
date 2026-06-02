sealed class AccessError implements Exception {
  const AccessError(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class TenantSuspendedError extends AccessError {
  const TenantSuspendedError()
      : super('403_TENANT_SUSPENDED', 'La suscripción del gimnasio está inactiva.');
}

class TenantPastDueError extends AccessError {
  const TenantPastDueError()
      : super('402_TENANT_PAST_DUE',
            'La suscripción del gimnasio tiene un pago pendiente.');
}

class BranchInactiveError extends AccessError {
  const BranchInactiveError()
      : super('403_BRANCH_INACTIVE', 'La sucursal está cerrada temporalmente.');
}

class MemberExpiredError extends AccessError {
  const MemberExpiredError()
      : super('403_MEMBER_EXPIRED', 'La membresía ha vencido.');
}

class MemberSuspendedError extends AccessError {
  const MemberSuspendedError()
      : super('403_MEMBER_SUSPENDED', 'El acceso del socio está suspendido.');
}

class BranchNotAllowedError extends AccessError {
  const BranchNotAllowedError()
      : super('403_BRANCH_NOT_ALLOWED', 'El socio no tiene acceso a esta sucursal.');
}

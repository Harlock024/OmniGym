import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/errors/access_errors.dart';

void main() {
  group('AccessError', () {
    test('TenantSuspendedError tiene code y message', () {
      const err = TenantSuspendedError();
      expect(err.code, '403_TENANT_SUSPENDED');
      expect(err.message, contains('suscripci'));
    });

    test('TenantPastDueError tiene code y message', () {
      const err = TenantPastDueError();
      expect(err.code, '402_TENANT_PAST_DUE');
      expect(err.message, contains('pago pendiente'));
    });

    test('BranchInactiveError tiene code y message', () {
      const err = BranchInactiveError();
      expect(err.code, '403_BRANCH_INACTIVE');
      expect(err.message, contains('cerrada'));
    });

    test('MemberExpiredError tiene code y message', () {
      const err = MemberExpiredError();
      expect(err.code, '403_MEMBER_EXPIRED');
      expect(err.message, contains('vencido'));
    });

    test('MemberSuspendedError tiene code y message', () {
      const err = MemberSuspendedError();
      expect(err.code, '403_MEMBER_SUSPENDED');
      expect(err.message, contains('suspendido'));
    });

    test('BranchNotAllowedError tiene code y message', () {
      const err = BranchNotAllowedError();
      expect(err.code, '403_BRANCH_NOT_ALLOWED');
      expect(err.message, contains('sucursal'));
    });

    test('toString incluye code y message', () {
      const err = TenantPastDueError();
      expect(err.toString(), contains('402_TENANT_PAST_DUE'));
      expect(err.toString(), contains('pago pendiente'));
    });

    test('AccessError es Exception', () {
      const err = BranchInactiveError();
      expect(err, isA<Exception>());
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:omnigym/core/models/app_user.dart';
import 'package:omnigym/core/models/module_access.dart';

AppUser operatorUser(
  String id,
  UserRole role, {
  String tenant = 'gym',
  Map<String, bool> permissions = const {},
}) => AppUser(
  id: id,
  name: id,
  email: '$id@example.test',
  tenantId: tenant,
  role: role,
  status: UserStatus.active,
  permissions: permissions,
);

void main() {
  test('receptionist profiles deserialize from backend documents without implicit grants', () {
    final user = AppUser.fromJson({
      'id': 'reception', 'name': 'Recepción', 'email': 'reception@example.test',
      'role': 'receptionist', 'status': 'active', 'tenant_id': 'gym',
    });
    expect(user.role, UserRole.receptionist);
    expect(ModuleAccess.home(user), '/no-access');
  });
  test('new receptionist has no modules and lands on the no-access screen', () {
    final user = operatorUser('reception', UserRole.receptionist);
    expect(
      appModules.any((module) => ModuleAccess.has(user, module.key)),
      isFalse,
    );
    expect(ModuleAccess.home(user), '/no-access');
  });
  test(
    'owner has every module; receptionist needs explicit boolean grants',
    () {
      final owner = operatorUser('owner', UserRole.owner);
      final reception = operatorUser(
        'reception',
        UserRole.receptionist,
        permissions: {'members': true, 'billing': false},
      );
      expect(
        appModules.every((module) => ModuleAccess.has(owner, module.key)),
        isTrue,
      );
      expect(ModuleAccess.home(reception), '/members');
      expect(ModuleAccess.has(reception, 'billing'), isFalse);
      expect(ModuleAccess.has(reception, 'scanner'), isFalse);
    },
  );
  test(
    'existing staff retains old baseline until an explicit map is saved',
    () {
      final staff = operatorUser('staff', UserRole.staff);
      expect(ModuleAccess.has(staff, 'scanner'), isTrue);
      expect(ModuleAccess.has(staff, 'members'), isFalse);
      final denied = staff.copyWith(
        permissions: {for (final m in appModules) m.key: false},
      );
      expect(ModuleAccess.has(denied, 'scanner'), isFalse);
      expect(ModuleAccess.home(denied), '/staff');
    },
  );
  test('QR availability blocks all roles and scanner-only profiles get a usable home', () {
    for (final role in UserRole.values) {
      final user = operatorUser('user', role, permissions: {'scanner': true});
      expect(ModuleAccess.canUse(user, 'scanner'), isFalse);
      expect(ModuleAccess.home(user), isNot('/scanner'));
    }
    final owner = operatorUser('owner', UserRole.owner);
    expect(ModuleAccess.canUse(owner, 'members'), isTrue);
    expect(ModuleAccess.has(owner, 'scanner'), isTrue);
    expect(
      ModuleAccess.isEnabled(ModuleAccess.moduleForRoute('/kiosk')),
      isFalse,
    );
  });
  test('suspension overrides any grants', () {
    final suspended = operatorUser(
      'owner',
      UserRole.owner,
    ).copyWith(status: UserStatus.suspended);
    expect(ModuleAccess.has(suspended, 'members'), isFalse);
    expect(ModuleAccess.home(suspended), '/access-suspended');
  });
  test(
    'staff manages only receptionists of the same gym, never itself or Owner',
    () {
      final staff = operatorUser('staff', UserRole.staff);
      expect(
        ModuleAccess.canManage(staff, operatorUser('r', UserRole.receptionist)),
        isTrue,
      );
      expect(
        ModuleAccess.canManage(
          staff,
          operatorUser('r', UserRole.receptionist, tenant: 'other'),
        ),
        isFalse,
      );
      expect(
        ModuleAccess.canManage(staff, operatorUser('s2', UserRole.staff)),
        isFalse,
      );
      expect(
        ModuleAccess.canManage(staff, operatorUser('o', UserRole.owner)),
        isFalse,
      );
      expect(ModuleAccess.canManage(staff, staff), isFalse);
    },
  );
  test('every operational route maps to its module, including kiosk and direct links', () {
    expect(ModuleAccess.moduleForRoute('/kiosk'), 'scanner');
    expect(ModuleAccess.moduleForRoute('/facturacion'), 'billing');
    expect(ModuleAccess.moduleForRoute('/members/detail'), 'members');
    expect(ModuleAccess.moduleForRoute('/dashboard/owner'), 'dashboard');
    expect(ModuleAccess.moduleForRoute('/profile'), isNull);
  });
}

/// New work logins use @omnigym.xyz. Old usernames still resolve to their
/// original Firebase identity. Delivery always uses the contact address.
abstract final class LoginIdentity {
  static const workDomain = 'omnigym.xyz';
  static const staffDomain = 'staff.omnigym.invalid';

  static String emailFor(String identifier) {
    final normalized = identifier.trim().toLowerCase();
    return normalized.contains('@') ? normalized : '$normalized@$staffDomain';
  }

  static bool isUsername(String identifier) =>
      RegExp(r'^[a-z0-9][a-z0-9._-]{2,79}$')
          .hasMatch(identifier.trim().toLowerCase());

  static bool isWorkLogin(String identifier) {
    final normalized = identifier.trim().toLowerCase();
    return !normalized.contains('@') ||
        normalized.endsWith('@$workDomain') ||
        normalized.endsWith('@$staffDomain');
  }
}

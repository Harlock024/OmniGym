/// Work usernames are separate from delivery addresses. These internal Firebase
/// identities have no mailbox. Keep the domain in sync with staff_accounts.js.
abstract final class LoginIdentity {
  static const staffDomain = 'staff.omnigym.invalid';

  static String emailFor(String identifier) {
    final normalized = identifier.trim().toLowerCase();
    return normalized.contains('@') ? normalized : '$normalized@$staffDomain';
  }

  static bool isUsername(String identifier) =>
      RegExp(r'^[a-z0-9][a-z0-9._-]{2,79}$')
          .hasMatch(identifier.trim().toLowerCase());
}

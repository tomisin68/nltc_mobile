/// Client-side form checks for the auth screens.
///
/// These exist to save a round trip and give a clearer message than Firebase
/// does — they are not the security boundary. The server and firestore.rules
/// remain the authority on what is actually acceptable.
abstract final class Validators {
  // Deliberately loose: `something@something.tld`. Anything stricter starts
  // rejecting addresses that genuinely deliver.
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Firebase's own floor. Rejecting shorter here means a clear message under
  /// the field instead of a `weak-password` bounce.
  static const minPasswordLength = 6;

  static String? required(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? 'Enter your $label.' : null;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(v)) return 'That email address does not look right.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password.';
    if (v.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Re-enter your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  /// Nigerian numbers are 11 digits local (`08012345678`) or 13 with the
  /// country code, and students type them with spaces, dashes and `+`. Count
  /// the digits and ignore the rest.
  static String? phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Enter your phone number.';
    if (digits.length < 10 || digits.length > 15) {
      return 'That phone number does not look right.';
    }
    return null;
  }
}

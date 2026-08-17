import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/app_user.dart';
import 'package:nltc/ui/core/state/session_controller.dart';

/// Who the compulsory email check applies to.
///
/// The gate stands in front of the entire app, so this predicate decides
/// whether somebody can use NLTC at all — and the two ways of being wrong fail
/// very differently. Letting an unverified student through is a gap. Gating an
/// admin strands them outside the console holding the only account that could
/// unlock it, because staff accounts are created by the backend with
/// `emailVerified: false` and no self-serve way to change that.
///
/// Production had 296 unverified students, 2 unverified center managers and 1
/// unverified admin the day this shipped.
///
/// Must stay in step with `requiresEmailVerification` in the website's
/// `src/utils/access.js` — a student gated on one platform and waved through on
/// the other is the same account contradicting itself.
void main() {
  AppUser user({String? role}) =>
      AppUser.fromMap('uid-1', {'email': 'student@example.ng', 'role': ?role});

  group('profileNeedsVerification', () {
    test('applies to students', () {
      expect(
        SessionController.profileNeedsVerification(user(role: 'student')),
        isTrue,
      );
    });

    test('applies to a profile with no role — that is what signup writes', () {
      expect(SessionController.profileNeedsVerification(user()), isTrue);
    });

    test('exempts every staff role', () {
      for (final role in const [
        'admin',
        'super_admin',
        'center_manager',
        'teacher',
      ]) {
        expect(
          SessionController.profileNeedsVerification(user(role: role)),
          isFalse,
          reason: '$role must never be held at the email gate',
        );
      }
    });

    test('exempts an account with no profile', () {
      // A competition entrant has no /users document — and so does a student
      // whose profile read has not landed yet. Both must fail open: the gate
      // closes a frame later, rather than flashing at somebody it never
      // applied to.
      expect(SessionController.profileNeedsVerification(null), isFalse);
    });
  });
}

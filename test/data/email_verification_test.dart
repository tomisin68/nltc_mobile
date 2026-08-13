import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/repositories/email_verification_repository.dart';
import 'package:nltc/data/services/api_client.dart';
import 'package:nltc/domain/models/app_user.dart';

/// Stands in for the backend so the classification can be exercised without a
/// network or a Firebase session. Only [post] is reached — the three OTP
/// endpoints are all POSTs.
class _StubApi extends ApiClient {
  _StubApi(this._outcome);

  /// Thrown from [post], or null to answer 200.
  final ApiException? _outcome;

  final List<String> calls = [];
  Object? lastBody;

  @override
  Future<Map<String, dynamic>> post(String path, [Object? body]) async {
    calls.add(path);
    lastBody = body;
    if (_outcome != null) throw _outcome;
    return const {'success': true};
  }
}

/// Email verification: what reaches the backend, and what a rejection means.
///
/// The distinction that matters is between a code that was merely wrong and a
/// code that is finished. The first leaves the student on the keypad; the
/// second has to send them to the resend button, because the backend has burnt
/// the code and no further guess can succeed.
void main() {
  EmailVerificationRepository repositoryThatFails(ApiException e) =>
      EmailVerificationRepository(api: _StubApi(e));

  group('what goes to the backend', () {
    test('send and resend name no account — the token identifies it', () async {
      final api = _StubApi(null);
      final repository = EmailVerificationRepository(api: api);

      await repository.send();
      expect(api.calls, ['/auth/send-otp']);
      expect(api.lastBody, isNull);

      await repository.resend();
      expect(api.calls.last, '/auth/resend-otp');
      expect(api.lastBody, isNull);
    });

    test('verify submits the code alone, trimmed', () async {
      final api = _StubApi(null);
      await EmailVerificationRepository(api: api).verify('  123456 ');

      expect(api.calls, ['/auth/verify-otp']);
      expect(api.lastBody, {'otp': '123456'});
    });
  });

  group('a rejected code', () {
    test('a wrong guess is retryable, and keeps the backend wording', () async {
      final repository = repositoryThatFails(
        const ApiException('Incorrect code', statusCode: 400),
      );

      await expectLater(
        repository.verify('999999'),
        throwsA(
          isA<VerificationFailure>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having((e) => e.message, 'message', 'Incorrect code'),
        ),
      );
    });

    test('the attempt cap is not retryable', () async {
      final repository = repositoryThatFails(
        const ApiException(
          'Too many incorrect codes — request a new one',
          statusCode: 429,
        ),
      );

      await expectLater(
        repository.verify('999999'),
        throwsA(
          isA<VerificationFailure>()
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    // Answered 400 rather than 429, so the status alone does not give it away.
    test('an expired code is not retryable', () async {
      final repository = repositoryThatFails(
        const ApiException(
          'Code expired — request a new one',
          statusCode: 400,
        ),
      );

      await expectLater(
        repository.verify('123456'),
        throwsA(
          isA<VerificationFailure>()
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('a code that was never sent is not retryable', () async {
      final repository = repositoryThatFails(
        const ApiException(
          'No verification pending for this account',
          statusCode: 400,
        ),
      );

      await expectLater(
        repository.verify('123456'),
        throwsA(
          isA<VerificationFailure>()
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });
  });

  group('failures that are not about the code', () {
    test('offline says so rather than blaming the digits', () async {
      final repository = repositoryThatFails(
        const ApiException('Could not reach the server', isOffline: true),
      );

      await expectLater(
        repository.verify('123456'),
        throwsA(
          isA<VerificationFailure>().having(
            (e) => e.message,
            'message',
            contains('No internet connection'),
          ),
        ),
      );
    });

    // The IP limiter, not the per-account attempt cap: nothing was guessed, so
    // the advice has to be "wait", not "your code is spent".
    test('a rate-limited send asks the student to wait', () async {
      final repository = repositoryThatFails(
        const ApiException('Too many requests', statusCode: 429),
      );

      await expectLater(
        repository.send(),
        throwsA(
          isA<VerificationFailure>().having(
            (e) => e.message,
            'message',
            contains('Wait a few minutes'),
          ),
        ),
      );
    });

    test('a lost session points at signing in again', () async {
      final repository = repositoryThatFails(
        const ApiException('Unauthorized', statusCode: 401),
      );

      await expectLater(
        repository.verify('123456'),
        throwsA(
          isA<VerificationFailure>().having(
            (e) => e.message,
            'message',
            contains('Sign in again'),
          ),
        ),
      );
    });
  });

  group('AppUser.emailVerified', () {
    test('reads the flag the backend writes', () {
      final user = AppUser.fromMap('uid-1', const {'emailVerified': true});
      expect(user.emailVerified, isTrue);
    });

    // Every account created before the OTP flow existed has no such field.
    // Reading absent as unverified is correct — they never verified.
    test('an account predating the field reads as unverified', () {
      final user = AppUser.fromMap('uid-1', const {'email': 'ada@test.com'});
      expect(user.emailVerified, isFalse);
    });

    test('survives the round trip through the on-device cache', () {
      final user = AppUser.fromMap('uid-1', const {'emailVerified': true});
      expect(AppUser.fromMap('uid-1', user.toJson()).emailVerified, isTrue);
    });

    // The copy helpers exist for optimistic patches of self-editable fields.
    // Verification is not one of them, so it must carry through untouched
    // rather than being reset by an unrelated profile save.
    test('a profile edit does not disturb it', () {
      final user = AppUser.fromMap('uid-1', const {'emailVerified': true});
      expect(user.copyWithProfile(firstName: 'Ada').emailVerified, isTrue);
    });
  });
}

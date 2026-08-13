import '../services/api_client.dart';

/// A rejected verification attempt, with the reason already fit to show.
///
/// [retryable] separates "that code was wrong, try the next one" from the
/// dead ends — an expired code, or five wrong guesses — where the only way
/// forward is a fresh send. The screen uses it to decide whether to leave the
/// student on the keypad or push them at the resend button.
class VerificationFailure implements Exception {
  const VerificationFailure(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => 'VerificationFailure($message)';
}

/// Email verification against `/api/auth/*`.
///
/// The three endpoints take no arguments beyond the code: the backend reads the
/// uid and the destination address off the verified ID token, so this client
/// never names the account it is verifying and cannot point a code at an inbox
/// that isn't the signed-in student's.
class EmailVerificationRepository {
  EmailVerificationRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  /// How long the backend's code stays good. Shown to the student so the
  /// keypad can say why a code they left for lunch stopped working.
  static const codeLifetime = Duration(minutes: 10);

  /// Guesses the backend allows before it burns the code. Mirrors
  /// `MAX_OTP_ATTEMPTS` in `src/routes/authCustom.js`.
  static const maxAttempts = 5;

  /// Mails a fresh code to the signed-in student's own address.
  Future<void> send() => _post('/auth/send-otp');

  /// Mails a replacement, and resets the attempt counter with it.
  Future<void> resend() => _post('/auth/resend-otp');

  Future<void> _post(String path) async {
    try {
      await _api.post(path);
    } on ApiException catch (e) {
      throw VerificationFailure(_sendMessage(e));
    }
  }

  /// Submits [code]. Returns normally only when the backend has marked the
  /// account verified in both Firebase Auth and the profile document.
  Future<void> verify(String code) async {
    try {
      await _api.post('/auth/verify-otp', {'otp': code.trim()});
    } on ApiException catch (e) {
      throw VerificationFailure(
        _verifyMessage(e),
        // 429 is the attempt cap, not the IP rate limit, at this point: the
        // code is spent either way and a sixth guess cannot succeed.
        retryable: e.statusCode != 429 && !_isSpent(e.message),
      );
    }
  }

  /// True when the backend is saying the code itself is finished, rather than
  /// that this particular guess was wrong.
  static bool _isSpent(String message) {
    final m = message.toLowerCase();
    return m.contains('expired') ||
        m.contains('too many') ||
        m.contains('no verification pending');
  }

  static String _sendMessage(ApiException e) {
    if (e.isOffline) {
      return 'No internet connection. Reconnect and try again.';
    }
    if (e.statusCode == 429) {
      return 'Too many requests. Wait a few minutes before asking for '
          'another code.';
    }
    if (e.statusCode == 401) {
      return 'Your session expired. Sign in again to verify your email.';
    }
    return e.message;
  }

  static String _verifyMessage(ApiException e) {
    if (e.isOffline) {
      return 'No internet connection. Reconnect and try again.';
    }
    if (e.statusCode == 401) {
      return 'Your session expired. Sign in again to verify your email.';
    }
    // Everything else — a wrong code, an expired one, the attempt cap — the
    // backend words better than this layer could, so it is passed through.
    return e.message;
  }
}

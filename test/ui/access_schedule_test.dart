import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/access_state.dart';
import 'package:nltc/domain/models/app_user.dart';
import 'package:nltc/ui/core/state/session_controller.dart';

/// Fixed clock so these never depend on when they run.
final _now = DateTime.utc(2025, 6, 15, 15, 6, 40);
const _day = Duration(days: 1);

AppUser _user(Map<String, dynamic> fields) =>
    AppUser.fromMap('u1', {'email': 'student@example.com', ...fields});

AccessState _access(Map<String, dynamic> fields, {DateTime? at}) =>
    AccessState.evaluate(
      _user(fields),
      nowMs: (at ?? _now).millisecondsSinceEpoch,
    );

void main() {
  group('SessionController.accessCheckDelay', () {
    test('waits out the trial, landing just past the boundary', () {
      final trialEnd = _now.add(const Duration(hours: 2));
      final delay = SessionController.accessCheckDelay(
        _access({'trialEndsAt': trialEnd.millisecondsSinceEpoch}),
        _now,
      );

      // A second of slack, so the re-evaluation cannot race the boundary it is
      // waiting for.
      expect(delay, const Duration(hours: 2, seconds: 1));
    });

    test('a long trial is re-checked periodically rather than once', () {
      // A timer set three days out does not survive the device sleeping, and
      // the "2 days left" line has to tick down in between anyway.
      final delay = SessionController.accessCheckDelay(
        _access({
          'trialEndsAt': _now.add(_day * 3).millisecondsSinceEpoch,
        }),
        _now,
      );

      expect(delay, isNotNull);
      expect(delay! <= const Duration(hours: 6), isTrue);
    });

    test('a grant that already lapsed is re-checked immediately', () {
      final trialEnd = _now.subtract(const Duration(seconds: 5));
      // Evaluated before the boundary — this is the state the app is holding
      // when it comes back from the background having missed the expiry.
      final stale = _access(
        {'trialEndsAt': trialEnd.millisecondsSinceEpoch},
        at: trialEnd.subtract(const Duration(minutes: 1)),
      );

      expect(stale.active, isTrue);
      expect(SessionController.accessCheckDelay(stale, _now), Duration.zero);
    });

    test('a locked account is not polled — only a payment can change it', () {
      final locked = _access({
        'trialEndsAt': _now.subtract(_day).millisecondsSinceEpoch,
      });

      expect(locked.isLocked, isTrue);
      expect(SessionController.accessCheckDelay(locked, _now), isNull);
    });

    test('a profile that has not loaded yet is not polled', () {
      expect(
        SessionController.accessCheckDelay(AccessState.evaluate(null), _now),
        isNull,
      );
    });

    test('an undated legacy grant is not polled', () {
      final legacy = _access({'lessonFeePaid': true});

      expect(legacy.reason, AccessReason.legacy);
      expect(SessionController.accessCheckDelay(legacy, _now), isNull);
    });

    test('a subscription is watched the same way a trial is', () {
      final delay = SessionController.accessCheckDelay(
        _access({
          'plan': 'pro',
          'planExpiresAt': _now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        }),
        _now,
      );

      expect(delay, const Duration(hours: 1, seconds: 1));
    });
  });
}

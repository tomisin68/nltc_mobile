import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/access_state.dart';
import 'package:nltc/domain/models/app_user.dart';

/// Fixed clock so these never depend on when they run.
const _now = 1750000000000; // 2025-06-15T15:06:40Z
const _day = 86400000;

AppUser _user(Map<String, dynamic> fields) =>
    AppUser.fromMap('u1', {'email': 'student@example.com', ...fields});

void main() {
  group('AccessState.evaluate', () {
    test('an unknown profile stays open rather than flashing a paywall', () {
      final access = AccessState.evaluate(null, nowMs: _now);

      expect(access.known, isFalse);
      expect(access.active, isTrue);
      expect(access.reason, AccessReason.loading);
      expect(access.isLocked, isFalse);
    });

    test('staff are never gated by a student fee', () {
      final access = AccessState.evaluate(
        _user({'role': 'admin'}),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.reason, AccessReason.staff);
    });

    test('a dated lesson fee unlocks and reports days left', () {
      final access = AccessState.evaluate(
        _user({
          'lessonFeePaid': true,
          'lessonFeeExpiresAt': _now + 10 * _day,
        }),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.reason, AccessReason.lessonFee);
      expect(access.daysLeft, 10);
      expect(access.everPaid, isTrue);
    });

    test('a dated subscription unlocks', () {
      final access = AccessState.evaluate(
        _user({'plan': 'pro', 'planExpiresAt': _now + 30 * _day}),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.reason, AccessReason.plan);
      expect(access.daysLeft, 30);
    });

    test('a paid flag with no dates anywhere is grandfathered in', () {
      final access = AccessState.evaluate(
        _user({'lessonFeePaid': true}),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.reason, AccessReason.legacy);
    });

    test('an undated plan does not resurrect an expired lesson fee', () {
      // The case the legacy rule exists to exclude: an admin sets plan: 'pro'
      // without planExpiresAt on an account whose lesson fee has lapsed.
      final access = AccessState.evaluate(
        _user({
          'plan': 'pro',
          'lessonFeePaid': true,
          'lessonFeeExpiresAt': _now - _day,
        }),
        nowMs: _now,
      );

      expect(access.active, isFalse);
      expect(access.reason, AccessReason.expired);
    });

    test('the trial unlocks and rounds days left up', () {
      final access = AccessState.evaluate(
        _user({'trialEndsAt': _now + _day + 1000}),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.reason, AccessReason.trial);
      expect(access.isOnTrial, isTrue);
      expect(access.trialDaysLeft, 2);
      expect(access.everPaid, isFalse);
    });

    test('a lapsed subscription reports expired, with the lapse date', () {
      final access = AccessState.evaluate(
        _user({'plan': 'pro', 'planExpiresAt': _now - 5 * _day}),
        nowMs: _now,
      );

      expect(access.isLocked, isTrue);
      expect(access.reason, AccessReason.expired);
      expect(access.everPaid, isTrue);
      expect(
        access.expiresAt?.millisecondsSinceEpoch,
        _now - 5 * _day,
      );
    });

    test('a used-up trial with no payment reports trialEnded', () {
      final access = AccessState.evaluate(
        _user({'trialEndsAt': _now - _day}),
        nowMs: _now,
      );

      expect(access.isLocked, isTrue);
      expect(access.reason, AccessReason.trialEnded);
      expect(access.isOnTrial, isFalse);
    });

    test('an account with no grant at all reports unpaid', () {
      final access = AccessState.evaluate(_user({}), nowMs: _now);

      expect(access.isLocked, isTrue);
      expect(access.reason, AccessReason.unpaid);
      expect(access.expiresAt, isNull);
    });
  });

  group('the three free days', () {
    // The signup path: trialEndsAt is stamped three days out and nothing else
    // on the account grants anything.
    AppUser trialUser(int endsAt) =>
        _user({'plan': 'free', 'studentMode': 'online', 'trialEndsAt': endsAt});

    test('unlocks everything from the moment the account is made', () {
      final access = AccessState.evaluate(
        trialUser(_now + 3 * _day),
        nowMs: _now,
      );

      expect(access.active, isTrue, reason: 'every gate reads this one flag');
      expect(access.isLocked, isFalse);
      expect(access.reason, AccessReason.trial);
      expect(access.trialDaysLeft, 3);
    });

    test('stays unlocked for the whole of the last day', () {
      final access = AccessState.evaluate(
        trialUser(_now + 1000),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.trialDaysLeft, 1);
    });

    test('locks on the millisecond it runs out, not a day later', () {
      final trialEnd = _now + 3 * _day;

      expect(
        AccessState.evaluate(trialUser(trialEnd), nowMs: trialEnd - 1).active,
        isTrue,
      );

      // Exactly at the boundary the trial is over: `now < trialEnd` is false.
      final atBoundary = AccessState.evaluate(
        trialUser(trialEnd),
        nowMs: trialEnd,
      );
      expect(atBoundary.active, isFalse);
      expect(atBoundary.isLocked, isTrue);
      expect(atBoundary.reason, AccessReason.trialEnded);
      expect(atBoundary.isOnTrial, isFalse);
      expect(atBoundary.trialDaysLeft, 0);
    });

    test('a payment during the trial takes over, and outlives it', () {
      final user = _user({
        'plan': 'pro',
        'planExpiresAt': _now + 30 * _day,
        'trialEndsAt': _now + _day,
      });

      final during = AccessState.evaluate(user, nowMs: _now);
      expect(during.reason, AccessReason.plan);
      expect(during.isOnTrial, isTrue, reason: 'the window is still open');

      // Two days on, the trial is gone and the subscription is carrying them.
      final after = AccessState.evaluate(user, nowMs: _now + 2 * _day);
      expect(after.active, isTrue);
      expect(after.reason, AccessReason.plan);
      expect(after.isOnTrial, isFalse);
    });

    test('a trial that ran out is not described as an expired payment', () {
      final ended = AccessState.evaluate(
        trialUser(_now - _day),
        nowMs: _now,
      );
      final lapsed = AccessState.evaluate(
        _user({'plan': 'pro', 'planExpiresAt': _now - _day}),
        nowMs: _now,
      );

      expect(ended.lockNote, contains('free trial'));
      expect(lapsed.lockNote, contains('expired'));
      expect(ended.lockNote, isNot(lapsed.lockNote));
    });
  });

  group('isPro — the bar the three Pro-only features sit behind', () {
    test('a paid subscription clears it', () {
      final access = AccessState.evaluate(
        _user({'plan': 'pro', 'planExpiresAt': _now + 30 * _day}),
        nowMs: _now,
      );

      expect(access.isPro, isTrue);
    });

    test('a centre lesson fee clears it — they have paid too', () {
      final access = AccessState.evaluate(
        _user({
          'studentMode': 'physical',
          'lessonFeePaid': true,
          'lessonFeeExpiresAt': _now + 10 * _day,
        }),
        nowMs: _now,
      );

      expect(access.isPro, isTrue);
    });

    test('staff clear it — their access never came from a fee', () {
      for (final role in ['admin', 'super_admin', 'center_manager', 'teacher']) {
        final access = AccessState.evaluate(_user({'role': role}), nowMs: _now);
        expect(access.isPro, isTrue, reason: role);
      }
    });

    test('a grandfathered record clears it', () {
      final access = AccessState.evaluate(
        _user({'lessonFeePaid': true}),
        nowMs: _now,
      );

      expect(access.reason, AccessReason.legacy);
      expect(access.isPro, isTrue);
    });

    test('a brand-new free account on trial does NOT clear it', () {
      // The whole point: the trial is active, so lessons, CBT and notes are
      // open, but nobody has paid — messages, live classes and Wrapped are not
      // part of a free account.
      final access = AccessState.evaluate(
        _user({
          'plan': 'free',
          'studentMode': 'online',
          'trialEndsAt': _now + 3 * _day,
        }),
        nowMs: _now,
      );

      expect(access.active, isTrue);
      expect(access.isLocked, isFalse);
      expect(access.isPro, isFalse);
    });

    test('neither does a used-up trial, or an account with no grant', () {
      expect(
        AccessState.evaluate(
          _user({'trialEndsAt': _now - _day}),
          nowMs: _now,
        ).isPro,
        isFalse,
      );
      expect(AccessState.evaluate(_user({}), nowMs: _now).isPro, isFalse);
    });

    test('a lapsed subscription loses it', () {
      final access = AccessState.evaluate(
        _user({'plan': 'pro', 'planExpiresAt': _now - _day}),
        nowMs: _now,
      );

      expect(access.reason, AccessReason.expired);
      expect(access.isPro, isFalse);
    });

    test('an unknown profile clears it, so nobody is upsold their own plan', () {
      final access = AccessState.evaluate(null, nowMs: _now);

      expect(access.known, isFalse);
      expect(access.isPro, isTrue);
    });

    test('a payment mid-trial clears it from that moment', () {
      final user = _user({
        'plan': 'pro',
        'planExpiresAt': _now + 30 * _day,
        'trialEndsAt': _now + _day,
      });

      final access = AccessState.evaluate(user, nowMs: _now);
      expect(access.isOnTrial, isTrue, reason: 'the window is still open');
      expect(access.reason, AccessReason.plan);
      expect(access.isPro, isTrue, reason: 'the payment is what counts');
    });
  });

  group('lapsesAt', () {
    test('is when an active grant runs out', () {
      final access = AccessState.evaluate(
        _user({'trialEndsAt': _now + 3 * _day}),
        nowMs: _now,
      );

      expect(
        access.lapsesAt?.millisecondsSinceEpoch,
        _now + 3 * _day,
      );
    });

    test('is null once locked — nothing changes without a payment', () {
      final access = AccessState.evaluate(
        _user({'trialEndsAt': _now - _day}),
        nowMs: _now,
      );

      expect(access.isLocked, isTrue);
      expect(access.expiresAt, isNotNull, reason: 'we still show the date');
      expect(access.lapsesAt, isNull);
    });

    test('is null for a grant with no end date', () {
      final access = AccessState.evaluate(
        _user({'lessonFeePaid': true}),
        nowMs: _now,
      );

      expect(access.reason, AccessReason.legacy);
      expect(access.lapsesAt, isNull);
    });
  });

  group('equality', () {
    test('two evaluations of the same profile at the same time match', () {
      final user = _user({'trialEndsAt': _now + 2 * _day});

      expect(
        AccessState.evaluate(user, nowMs: _now),
        AccessState.evaluate(user, nowMs: _now),
      );
    });

    test('the day the trial ticks down is a change the UI must see', () {
      final user = _user({'trialEndsAt': _now + 2 * _day});

      expect(
        AccessState.evaluate(user, nowMs: _now),
        isNot(AccessState.evaluate(user, nowMs: _now + _day)),
      );
    });
  });
}

import 'app_user.dart';

/// Why an account is (or isn't) unlocked.
enum AccessReason {
  staff,
  lessonFee,
  plan,
  legacy,
  trial,
  expired,
  trialEnded,
  unpaid,
  loading,
}

/// The result of evaluating whether an account currently has access.
///
/// Direct port of `src/utils/access.js` on the web. The two implementations
/// must agree — a student locked out on the website but let in on the app (or
/// the reverse) is a support ticket every time. Keep them in step.
class AccessState {
  const AccessState({
    required this.known,
    required this.active,
    required this.reason,
    this.expiresAt,
    this.daysLeft,
    this.isOnTrial = false,
    this.trialDaysLeft = 0,
    this.everPaid = false,
  });

  /// `false` while the profile is still loading — never lock the UI on this.
  final bool known;

  /// `true` = full platform access.
  final bool active;

  final AccessReason reason;

  /// When the current grant lapses, or when it lapsed.
  final DateTime? expiresAt;

  final int? daysLeft;
  final bool isOnTrial;
  final int trialDaysLeft;

  /// Has this account ever held a paid grant?
  final bool everPaid;

  /// `true` only when we know the profile and it is locked.
  bool get isLocked => known && !active;

  /// Whether this account has actually been paid for — the bar the Pro-only
  /// features sit behind.
  ///
  /// Deliberately not the same question as [active]. The three free days make an
  /// account active without anybody having paid, and Messages, My Wrapped and
  /// Live Classes are not part of what a free account gets: they are the reason
  /// to upgrade. Everything else — lessons, CBT, notes, mock exams — stays open
  /// for the whole trial, so a new student still gets a real look at the
  /// platform. See [ProFeature] for the three and the copy that explains them.
  ///
  /// Staff pass because their access never came from a fee in the first place,
  /// and a grandfathered record passes because a paid flag with no dates is the
  /// only trace those accounts have of the payment they made.
  ///
  /// An unknown profile passes, for the same reason [active] does: a student who
  /// has paid must never be shown an upsell for something they own while their
  /// profile is still loading. The gate closes a frame later, once the answer is
  /// in — the opposite order would flash a paywall at a paying student on every
  /// cold start.
  bool get isPro => switch (reason) {
        AccessReason.staff ||
        AccessReason.lessonFee ||
        AccessReason.plan ||
        AccessReason.legacy ||
        AccessReason.loading =>
          true,
        AccessReason.trial ||
        AccessReason.expired ||
        AccessReason.trialEnded ||
        AccessReason.unpaid =>
          false,
      };

  /// When this state stops being true on its own, with no profile write.
  ///
  /// Only an *active* grant expires by itself — a locked account cannot become
  /// unlocked without a payment, which arrives as a profile update. This is
  /// what [SessionController] arms its timer on, so the lock engages the moment
  /// the third day runs out rather than at the next rebuild.
  DateTime? get lapsesAt => active ? expiresAt : null;

  @override
  bool operator ==(Object other) =>
      other is AccessState &&
      other.known == known &&
      other.active == active &&
      other.reason == reason &&
      other.expiresAt == expiresAt &&
      other.daysLeft == daysLeft &&
      other.isOnTrial == isOnTrial &&
      other.trialDaysLeft == trialDaysLeft &&
      other.everPaid == everPaid;

  @override
  int get hashCode => Object.hash(
        known,
        active,
        reason,
        expiresAt,
        daysLeft,
        isOnTrial,
        trialDaysLeft,
        everPaid,
      );

  static const _staffRoles = {
    'admin',
    'super_admin',
    'center_manager',
    'teacher',
  };

  static int _daysBetween(int ms, int now) {
    final diff = ms - now;
    if (diff <= 0) return 0;
    return (diff / 86400000).ceil();
  }

  /// Evaluates access for [user] at [now] (millis since epoch, for testability).
  ///
  /// Every grant is dated. A grant with no date only counts when the account
  /// has no dated grant at all (genuinely grandfathered records) — otherwise an
  /// admin activation that sets `plan: 'pro'` without `planExpiresAt` would
  /// keep an expired lesson fee alive forever.
  factory AccessState.evaluate(AppUser? user, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

    if (user == null) {
      // Unknown profile: stay open rather than flashing a paywall at someone
      // who has actually paid.
      return const AccessState(
        known: false,
        active: true,
        reason: AccessReason.loading,
      );
    }

    final lessonExp = user.lessonFeeExpiresAt;
    final planExp = user.planExpiresAt;
    final trialEnd = user.trialEndsAt;
    final hasPlan = user.plan != null && user.plan != 'free';

    final everPaid = user.lessonFeePaid ||
        lessonExp != null ||
        planExp != null ||
        user.lessonFeePaidAt != null ||
        user.planActivatedAt != null;

    final isOnTrial = trialEnd != null && now < trialEnd;
    final trialDaysLeft = isOnTrial ? _daysBetween(trialEnd, now) : 0;

    AccessState base({
      required bool active,
      required AccessReason reason,
      DateTime? expiresAt,
      int? daysLeft,
    }) =>
        AccessState(
          known: true,
          active: active,
          reason: reason,
          expiresAt: expiresAt,
          daysLeft: daysLeft,
          isOnTrial: isOnTrial,
          trialDaysLeft: trialDaysLeft,
          everPaid: everPaid,
        );

    // Staff are never gated by a student fee.
    if (_staffRoles.contains(user.role)) {
      return base(active: true, reason: AccessReason.staff);
    }

    // 1. Physical-centre lesson fee — dated grant.
    if (user.lessonFeePaid && lessonExp != null && lessonExp > now) {
      return base(
        active: true,
        reason: AccessReason.lessonFee,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(lessonExp),
        daysLeft: _daysBetween(lessonExp, now),
      );
    }

    // 2. Online subscription — dated grant. This is what the app sells.
    if (hasPlan && planExp != null && planExp > now) {
      return base(
        active: true,
        reason: AccessReason.plan,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(planExp),
        daysLeft: _daysBetween(planExp, now),
      );
    }

    // 3. Grandfathered records — a paid flag with no expiry date anywhere.
    if (lessonExp == null && planExp == null && (user.lessonFeePaid || hasPlan)) {
      return base(active: true, reason: AccessReason.legacy);
    }

    // 4. Free trial.
    if (isOnTrial) {
      return base(
        active: true,
        reason: AccessReason.trial,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(trialEnd),
        daysLeft: trialDaysLeft,
      );
    }

    // Locked — report the most useful reason and when access ran out.
    final lapsed = [lessonExp ?? 0, planExp ?? 0].reduce((a, b) => a > b ? a : b);
    if (everPaid) {
      return base(
        active: false,
        reason: AccessReason.expired,
        expiresAt:
            lapsed > 0 ? DateTime.fromMillisecondsSinceEpoch(lapsed) : null,
      );
    }
    if (trialEnd != null) {
      return base(
        active: false,
        reason: AccessReason.trialEnded,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(trialEnd),
      );
    }
    return base(active: false, reason: AccessReason.unpaid);
  }

  /// Student-facing explanation for the paywall screen.
  String get headline => switch (reason) {
        AccessReason.expired => 'Your access has expired',
        AccessReason.trialEnded => 'Your free trial has ended',
        AccessReason.unpaid => 'Activate your account',
        _ => 'Activate your account',
      };

  String get subline => switch (reason) {
        AccessReason.expired =>
          'Renew to get straight back to your lessons and practice tests.',
        AccessReason.trialEnded =>
          'You have used your 3 free days. Activate to keep going.',
        _ => 'One payment unlocks every subject, past question and mock exam.',
      };

  /// One line for the gates that sit next to a blocked action.
  ///
  /// Kept here so the exam sheet and the download button never disagree about
  /// why a student is being stopped — and so a trial that has run out is never
  /// described as an expired payment to someone who has not paid.
  String get lockNote => switch (reason) {
        AccessReason.expired =>
          'Your access has expired. Renew on nltc.com.ng to carry on.',
        AccessReason.trialEnded =>
          'Your 3-day free trial has ended. Activate on nltc.com.ng to carry on.',
        _ => 'Activate your account on nltc.com.ng to unlock this.',
      };
}

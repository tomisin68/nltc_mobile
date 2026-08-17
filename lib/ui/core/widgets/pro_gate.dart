/// The gates in front of the three Pro-only features.
///
/// A free account — including one still inside its three free days — can see
/// that Messages, Live Classes and My Wrapped exist, and is told what they are,
/// but cannot open them. Two shapes, one piece of copy: [ProUpsellView] replaces
/// a whole gated view, and [showProUpsell] answers a tap on something that has
/// no view of its own to replace.
///
/// Both read [AccessState.isPro], never [AccessState.active] — an active account
/// is not necessarily a paid one, and the trial is exactly the case this exists
/// for. See [ProFeature].
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/access_state.dart';
import '../../../domain/pro_features.dart';
import '../state/dashboard_controller.dart';
import '../state/session_controller.dart';
import '../theme/app_palette.dart';

/// The icon each feature is drawn with — the same one its sidebar link uses, so
/// the gate reads as the thing the student just tapped.
IconData proFeatureIcon(ProFeature feature) => switch (feature) {
      ProFeature.messages => Icons.chat_bubble_rounded,
      ProFeature.liveClasses => Icons.sensors_rounded,
      ProFeature.wrapped => Icons.auto_awesome_rounded,
    };

/// Raises the upsell as a sheet.
///
/// For the taps that have nowhere to land: My Wrapped is a route rather than a
/// dashboard view, and "Join" on a live class sits on a screen the student is
/// allowed to be on. A sheet keeps them where they were, which matters when the
/// thing behind it — the class list, the drawer they just came from — is what
/// they were looking at.
Future<void> showProUpsell(BuildContext context, ProFeature feature) {
  final access = context.read<SessionController>().access;
  final dashboard = context.read<DashboardController>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s5,
        Tokens.s4,
        Tokens.s6,
      ),
      child: SingleChildScrollView(
        child: ProUpsellPanel(
          feature: feature,
          access: access,
          onUpgrade: () {
            Navigator.of(sheetContext).pop();
            dashboard.select(DashboardView.settings);
          },
        ),
      ),
    ),
  );
}

/// What a free account sees in place of a Pro-only view.
///
/// Sibling of `LockedView`, and deliberately not the same screen: that one is
/// for an account that has lapsed and says so in red, while this is an offer to
/// somebody whose account is working fine. Reusing it would tell a brand-new
/// student on day one that their access had expired.
class ProUpsellView extends StatelessWidget {
  const ProUpsellView({super.key, required this.feature, required this.access});

  final ProFeature feature;
  final AccessState access;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.s5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  isDark ? scheme.surfaceContainerLow : BlueprintPalette.white,
              borderRadius: BorderRadius.circular(Tokens.rLg),
              border: Border(
                top: BorderSide(color: scheme.primary, width: 4),
              ),
              boxShadow: [
                BoxShadow(
                  color: BlueprintPalette.b900.withValues(alpha: 0.10),
                  blurRadius: 40,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s6,
                vertical: Tokens.s8,
              ),
              child: ProUpsellPanel(feature: feature, access: access),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pitch itself: badge, what the feature is, what upgrading gets, the way
/// out. Hosted by [ProUpsellView] and [showProUpsell] alike.
class ProUpsellPanel extends StatelessWidget {
  const ProUpsellPanel({
    super.key,
    required this.feature,
    required this.access,
    this.onUpgrade,
  });

  final ProFeature feature;
  final AccessState access;

  /// Defaults to sending the student to Settings, where the packages are.
  final VoidCallback? onUpgrade;

  void _upgrade(BuildContext context) {
    final onUpgrade = this.onUpgrade;
    if (onUpgrade != null) {
      onUpgrade();
      return;
    }
    context.read<DashboardController>().select(DashboardView.settings);
  }

  /// The line under the button.
  ///
  /// A lapsed account is told the truth about why it is out — it has paid before
  /// and this is not the moment to describe its access as "free". Everyone else
  /// is reminded what they *do* have, so the gate reads as one feature held back
  /// rather than as the app shutting them out.
  String get _footnote => access.isLocked
      ? access.lockNote
      : 'Everything else stays open: video lessons, CBT practice, quick tests, '
          'mock exams and study notes.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? scheme.primaryContainer : BlueprintPalette.b100,
            border: Border.all(color: scheme.primary, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(proFeatureIcon(feature), size: 28, color: scheme.primary),
        ),
        const SizedBox(height: Tokens.s4),
        const ProBadge(),
        const SizedBox(height: Tokens.s3),
        Text(
          'Unlock ${feature.label}',
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          feature.body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.65,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Tokens.s5),
        for (final perk in feature.perks)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s2),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Text(
                    perk,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Tokens.s4),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _upgrade(context),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: const Icon(Icons.rocket_launch_rounded, size: 18),
            label: Text(access.isLocked ? 'Renew Now' : 'Upgrade to Pro'),
          ),
        ),
        const SizedBox(height: Tokens.s3),
        Text(
          _footnote,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

/// The "PRO" pill — on the upsell panel, and on the sidebar links a free account
/// cannot follow.
///
/// A pill rather than the padlock the locked links carry: those two states are
/// different and a student should be able to tell them apart at a glance. A
/// padlock means the account has lapsed and everything is gone; this means one
/// feature is on the other side of an upgrade.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          // rgba(29,111,242,.14) — the same wash the sidebar's Pro pill uses.
          color: const Color(0x241D6FF2),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              size: 10,
              color: BlueprintPalette.b700,
            ),
            const SizedBox(width: 3),
            const Text(
              'PRO',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: BlueprintPalette.b700,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

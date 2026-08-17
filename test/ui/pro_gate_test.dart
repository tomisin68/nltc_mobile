import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/access_state.dart';
import 'package:nltc/domain/models/app_user.dart';
import 'package:nltc/domain/pro_features.dart';
import 'package:nltc/ui/core/state/dashboard_controller.dart';
import 'package:nltc/ui/core/widgets/pro_gate.dart';
import 'package:provider/provider.dart';

/// The panel a free account meets in place of Messages, Live Classes or My
/// Wrapped.
///
/// Two things matter here and neither is decoration: it must always offer a way
/// to pay, and it must not tell a student the wrong story about their own
/// account — a brand-new signup is not "expired", and somebody whose plan has
/// lapsed is not on a free account being offered an extra.
const _now = 1750000000000; // 2025-06-15T15:06:40Z
const _day = 86400000;

AccessState _access(Map<String, dynamic> fields) => AccessState.evaluate(
      AppUser.fromMap('u1', {'email': 'student@example.ng', ...fields}),
      nowMs: _now,
    );

void main() {
  late DashboardController dashboard;

  setUp(() => dashboard = DashboardController());
  tearDown(() => dashboard.dispose());

  Future<void> pumpPanel(
    WidgetTester tester, {
    required ProFeature feature,
    required AccessState access,
  }) =>
      tester.pumpWidget(
        ChangeNotifierProvider<DashboardController>.value(
          value: dashboard,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProUpsellPanel(feature: feature, access: access),
              ),
            ),
          ),
        ),
      );

  final onTrial = _access({
    'plan': 'free',
    'studentMode': 'online',
    'trialEndsAt': _now + 3 * _day,
  });

  testWidgets('names the feature and what it gets you', (tester) async {
    await pumpPanel(tester, feature: ProFeature.messages, access: onTrial);

    expect(find.text('Unlock Messages'), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    for (final perk in ProFeature.messages.perks) {
      expect(find.text(perk), findsOneWidget);
    }
  });

  testWidgets('sends a free student to the packages in Settings',
      (tester) async {
    await pumpPanel(tester, feature: ProFeature.wrapped, access: onTrial);

    expect(dashboard.view, DashboardView.home);
    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pump();

    expect(dashboard.view, DashboardView.settings);
  });

  testWidgets('tells a trial account what it still has, not that it expired',
      (tester) async {
    await pumpPanel(tester, feature: ProFeature.liveClasses, access: onTrial);

    expect(find.textContaining('video lessons'), findsOneWidget);
    expect(find.textContaining('expired'), findsNothing);
  });

  testWidgets('a lapsed account is told the truth instead, and asked to renew',
      (tester) async {
    final expired = _access({'plan': 'pro', 'planExpiresAt': _now - _day});

    await pumpPanel(tester, feature: ProFeature.wrapped, access: expired);

    expect(find.text('Renew Now'), findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsNothing);
    expect(find.text(expired.lockNote), findsOneWidget);
  });

  testWidgets('the override is used when one is given — the sheet needs to pop '
      'itself first', (tester) async {
    var pressed = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<DashboardController>.value(
        value: dashboard,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProUpsellPanel(
                feature: ProFeature.messages,
                access: onTrial,
                onUpgrade: () => pressed++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upgrade to Pro'));
    await tester.pump();

    expect(pressed, 1);
    expect(dashboard.view, DashboardView.home, reason: 'the host navigates');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/wrapped_stats.dart';
import 'package:nltc/ui/wrapped/wrapped_card.dart';

/// The card is captured to a PNG at a fixed size, so anything that changes how
/// tall its content measures crops the shared image instead of reflowing it.
/// These guard the two ways that happened.
void main() {
  /// A month with everything filled in and nothing short about it — the longest
  /// title, six-figure counts, a subject name that will not fit, and a duration
  /// in the widest of its three shapes.
  WrappedStats worstCase() => WrappedStats(
        month: DateTime(2026, 9),
        sittings: 148,
        questions: 12480,
        correct: 11106,
        activeDays: 28,
        subjects: const [
          SubjectTally(
            subject: 'Christian Religious Studies',
            questions: 4820,
            correct: 4331,
            sittings: 61,
          ),
          SubjectTally(
            subject: 'Further Mathematics',
            questions: 3960,
            correct: 3402,
            sittings: 44,
          ),
        ],
        bestScore: 100,
        bestScoreSubject: 'Christian Religious Studies',
        timeStudied: const Duration(hours: 128, minutes: 45),
        streak: 365,
        xp: 98750,
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required WrappedStats stats,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          // Unbounded, the way `_CardPanel`'s FittedBox measures it.
          child: UnconstrainedBox(
            child: WrappedCard(stats: stats, name: 'Adaeze'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('keeps its 4:5 capture size', (tester) async {
    await pumpCard(tester, stats: worstCase());

    expect(
      tester.getSize(find.byType(WrappedCard)),
      const Size(WrappedCard.width, WrappedCard.height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignores the system font size', (tester) async {
    // The bug this replaces: at a raised OS font size the column outgrew the
    // fixed height, and the shared PNG came out with its last line sliced in
    // half. The card must measure the same at every scale.
    for (final scale in [0.85, 1.0, 1.3, 2.0]) {
      await pumpCard(tester, stats: worstCase(), textScale: scale);

      expect(
        tester.getSize(find.byType(WrappedCard)),
        const Size(WrappedCard.width, WrappedCard.height),
        reason: 'text scale $scale resized the card',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'text scale $scale overflowed the card',
      );
    }
  });

  testWidgets('lays out an empty month without overflowing', (tester) async {
    // No subjects means the "most practised" block is absent and the Spacer
    // takes the slack instead — the other end of the same layout.
    await pumpCard(
      tester,
      stats: WrappedStats(
        month: DateTime(2026, 9),
        sittings: 0,
        questions: 0,
        correct: 0,
        activeDays: 0,
        subjects: const [],
        bestScore: 0,
        bestScoreSubject: null,
        timeStudied: null,
        streak: 0,
        xp: 0,
      ),
      textScale: 2,
    );

    expect(
      tester.getSize(find.byType(WrappedCard)),
      const Size(WrappedCard.width, WrappedCard.height),
    );
    expect(tester.takeException(), isNull);
  });
}

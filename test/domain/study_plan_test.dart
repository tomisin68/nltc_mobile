import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/study_plan.dart';

/// The weekly study timetable's scheduling rules.
///
/// A mirror of `src/tests/unit/studyPlan.test.js` in the website repo, because
/// the two implementations have to agree: the app and the browser both rebuild
/// the week, and a student must not get one timetable on their phone and a
/// different one in a tab.
///
/// The load-bearing test is the "journey" one — simulating a student working
/// through a whole syllabus week after week, and asserting no topic is ever
/// handed to them twice until the subject is finished. Everything else in the
/// feature is presentation; that property is the feature.
void main() {
  // ─── Fixtures ──────────────────────────────────────────────────────────────

  List<PlanTopic> topics(String subject, int n) => [
        for (var i = 0; i < n; i++)
          PlanTopic(id: '$subject-$i', topic: '$subject Topic ${i + 1}'),
      ];

  final fixture = <String, List<PlanTopic>>{
    'Biology': topics('Biology', 33),
    'Physics': topics('Physics', 40),
    'Chemistry': topics('Chemistry', 30),
    'Mathematics': topics('Mathematics', 39),
    'Government': topics('Government', 45),
  };
  final subjects = fixture.keys.toList();

  /// The `YYYY-MM-DD` Monday [i] weeks after the origin.
  String keyForIndex(int i) {
    final d = DateTime.utc(2024, 1, 1).add(Duration(days: i * 7));
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Coverage must always be a prefix of each subject's topic order — the
  /// invariant behind "nothing gets left behind".
  void expectCoverageIsPrefixed(
    Set<String> covered, [
    Map<String, List<PlanTopic>>? source,
  ]) {
    (source ?? fixture).forEach((subject, list) {
      final flags = [
        for (final t in list) covered.contains(coverKey(subject, t.topic)),
      ];
      final firstGap = flags.indexOf(false);
      if (firstGap == -1) return;
      expect(flags.sublist(firstGap).every((f) => !f), isTrue,
          reason: '$subject has a covered topic after an uncovered one');
    });
  }

  ({Set<String> covered, List<String> handedOut, List<List<PlanSlot>> perWeek})
      runJourney({
    required List<String> chosen,
    required Map<String, List<PlanTopic>> topicsBySubject,
    required int weeks,
    String startKey = '2026-08-10',
    bool Function(PlanSlot slot, int week)? study,
  }) {
    final covered = <String>{};
    final handedOut = <String>[];
    final perWeek = <List<PlanSlot>>[];
    final decide = study ?? (_, _) => true;

    final start = weekIndexOf(startKey);
    for (var w = 0; w < weeks; w++) {
      final slots = buildWeek(
        subjects: chosen,
        topicsBySubject: topicsBySubject,
        covered: covered,
        weekStartKey: keyForIndex(start + w),
      );
      perWeek.add(slots);
      for (final slot in slots) {
        if (slot.rest) continue;
        final key = coverKey(slot.subject!, slot.topic!);
        handedOut.add(key);
        if (decide(slot, w)) covered.add(key);
      }
    }
    return (covered: covered, handedOut: handedOut, perWeek: perWeek);
  }

  // ─── Week arithmetic ───────────────────────────────────────────────────────

  group('week arithmetic', () {
    test('snaps every day of a week back to the same Monday', () {
      final keys = {
        for (var i = 0; i < 7; i++) weekKey(DateTime(2026, 8, 10 + i)),
      };
      expect(keys, {'2026-08-10'});
    });

    test('treats Sunday as the end of the week it began', () {
      expect(weekKey(DateTime(2026, 8, 16)), '2026-08-10'); // Sunday
      expect(weekKey(DateTime(2026, 8, 17)), '2026-08-17'); // Monday
    });

    test('crosses a month boundary without slipping', () {
      expect(weekKey(DateTime(2026, 9, 3)), '2026-08-31');
    });

    test('crosses a year boundary without slipping', () {
      // Thu 1 Jan 2026 falls in the week beginning Mon 29 Dec 2025.
      expect(weekKey(DateTime(2026, 1, 1)), '2025-12-29');
    });

    test('advances the week index by exactly one per week', () {
      expect(weekIndexOf('2026-08-17') - weekIndexOf('2026-08-10'), 1);
      expect(weekIndexOf('2024-01-01'), 0);
    });

    test('mondayOf returns a local midnight Monday', () {
      final m = mondayOf(DateTime(2026, 8, 13, 22, 45));
      expect(m.weekday, DateTime.monday);
      expect([m.hour, m.minute, m.second], [0, 0, 0]);
    });

    test('numbers the days of a week key from its Monday', () {
      expect(dayOfWeekKey('2026-08-10', 0).day, 10);
      expect(dayOfWeekKey('2026-08-10', 6).day, 16);
      expect(dayOfWeekKey('2026-08-10', 6).weekday, DateTime.sunday);
    });
  });

  // ─── Shape of a generated week ─────────────────────────────────────────────

  group('buildWeek', () {
    List<PlanSlot> base({
      List<String>? chosen,
      Set<String>? covered,
      String week = '2026-08-10',
    }) =>
        buildWeek(
          subjects: chosen ?? subjects,
          topicsBySubject: fixture,
          covered: covered ?? {},
          weekStartKey: week,
        );

    test('fills all seven days', () {
      final slots = base();
      expect(slots, hasLength(daysInWeek));
      expect(slots.every((s) => !s.rest), isTrue);
      expect([for (final s in slots) s.day], [0, 1, 2, 3, 4, 5, 6]);
    });

    test('carries the note id through, so a slot can link to its note', () {
      for (final slot in base()) {
        final n = int.parse(slot.topic!.split(' ').last) - 1;
        expect(slot.noteId, '${slot.subject}-$n');
      }
    });

    test('never repeats a topic inside one week', () {
      final keys = [for (final s in base()) coverKey(s.subject!, s.topic!)];
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('never puts the same subject on two days running', () {
      for (var n = minPlanSubjects; n <= subjects.length; n++) {
        final slots = base(chosen: subjects.take(n).toList());
        for (var i = 1; i < slots.length; i++) {
          expect(slots[i].subject, isNot(slots[i - 1].subject));
        }
      }
    });

    test('gives a different subject the Monday each week', () {
      final start = weekIndexOf('2026-08-10');
      final mondays = {
        for (var w = 0; w < 5; w++) base(week: keyForIndex(start + w)).first.subject,
      };
      expect(mondays.length, greaterThan(1));
    });

    test('is deterministic — same inputs, same week', () {
      final a = base();
      final b = base();
      for (var i = 0; i < a.length; i++) {
        expect(a[i].subject, b[i].subject);
        expect(a[i].topic, b[i].topic);
      }
    });

    test('returns nothing when no subjects are chosen', () {
      expect(base(chosen: const []), isEmpty);
    });

    test('skips topics already covered', () {
      final covered = {
        for (final t in fixture['Biology']!.take(30)) coverKey('Biology', t.topic),
      };
      for (final slot in base(covered: covered)) {
        if (slot.subject != 'Biology') continue;
        expect(covered.contains(coverKey('Biology', slot.topic!)), isFalse);
      }
    });

    test("hands a finished subject's day to one that still has topics", () {
      final covered = <String>{};
      for (final s in subjects.skip(1)) {
        for (final t in fixture[s]!) {
          covered.add(coverKey(s, t.topic));
        }
      }
      final slots = base(covered: covered);
      expect(slots.every((s) => !s.rest), isTrue);
      expect({for (final s in slots) s.subject}, {'Biology'});
      expect({for (final s in slots) s.topic}, hasLength(7));
    });

    test('gives rest days once every topic in every subject is covered', () {
      final covered = <String>{};
      fixture.forEach((s, list) {
        for (final t in list) {
          covered.add(coverKey(s, t.topic));
        }
      });
      final slots = base(covered: covered);
      expect(slots.every((s) => s.rest), isTrue);
      expect(slots.every((s) => s.subject == null), isTrue);
    });

    test('runs the week down to rest days when only a few topics remain', () {
      final covered = <String>{};
      fixture.forEach((s, list) {
        for (final t in list.skip(2)) {
          covered.add(coverKey(s, t.topic));
        }
      });
      expect(base(covered: covered).where((s) => s.rest), isEmpty);

      final nearlyDone = {...covered};
      for (final s in subjects.skip(1)) {
        for (final t in fixture[s]!.take(2)) {
          nearlyDone.add(coverKey(s, t.topic));
        }
      }
      final slots = base(covered: nearlyDone);
      expect(slots.where((s) => !s.rest), hasLength(2));
      expect(slots.where((s) => s.rest), hasLength(5));
    });
  });

  // ─── THE PROMISE ───────────────────────────────────────────────────────────

  group('the journey through a syllabus', () {
    test('never hands out the same topic twice while anything is uncovered', () {
      final run = runJourney(
        chosen: subjects,
        topicsBySubject: fixture,
        weeks: 30,
      );
      final seen = <String>{};
      for (final key in run.handedOut) {
        expect(seen.contains(key), isFalse, reason: '$key was handed out twice');
        seen.add(key);
      }
      expectCoverageIsPrefixed(run.covered);
    });

    test('covers every single topic in every subject, and then stops', () {
      final total = subjects.fold(0, (n, s) => n + fixture[s]!.length);
      final run = runJourney(
        chosen: subjects,
        topicsBySubject: fixture,
        weeks: 40,
      );

      expect(run.covered, hasLength(total));
      expect(run.handedOut, hasLength(total)); // nothing scheduled twice
      fixture.forEach((s, list) {
        for (final t in list) {
          expect(run.covered.contains(coverKey(s, t.topic)), isTrue);
        }
      });
    });

    test('re-offers a topic the student skipped, rather than skipping past it', () {
      final run = runJourney(
        chosen: subjects,
        topicsBySubject: fixture,
        weeks: 2,
        study: (_, week) => week > 0,
      );

      expect(run.covered, hasLength(7));
      expectCoverageIsPrefixed(run.covered);

      for (final slot in run.perWeek[0]) {
        final list = fixture[slot.subject]!;
        final index = list.indexWhere((t) => t.topic == slot.topic);
        final coveredInSubject = list
            .where((t) => run.covered.contains(coverKey(slot.subject!, t.topic)))
            .length;
        expect(index, lessThanOrEqualTo(coveredInSubject));
      }
    });

    test('holds the promise for every allowed number of subjects', () {
      for (var n = minPlanSubjects; n <= subjects.length; n++) {
        final chosen = subjects.take(n).toList();
        final total = chosen.fold(0, (sum, s) => sum + fixture[s]!.length);
        final run = runJourney(
          chosen: chosen,
          topicsBySubject: fixture,
          weeks: 60,
        );
        expect(run.handedOut.toSet(), hasLength(run.handedOut.length));
        expect(run.covered, hasLength(total));
      }
    });

    test('keeps the promise when a subject is much shorter than the others', () {
      final lopsided = <String, List<PlanTopic>>{
        'Short': topics('Short', 3),
        ...fixture,
      };
      final chosen = ['Short', 'Biology', 'Physics', 'Chemistry'];
      final total = chosen.fold(0, (n, s) => n + lopsided[s]!.length);

      final run = runJourney(
        chosen: chosen,
        topicsBySubject: lopsided,
        weeks: 60,
      );
      expect(run.handedOut.toSet(), hasLength(run.handedOut.length));
      expect(run.covered, hasLength(total));
    });
  });

  // ─── Progress ──────────────────────────────────────────────────────────────

  group('progress', () {
    test('counts nothing covered at the start', () {
      final p = subjectProgress('Biology', fixture, {});
      expect(p.done, 0);
      expect(p.total, 33);
      expect(p.complete, isFalse);
      expect(p.fraction, 0);
    });

    test('reports complete only when every topic is covered', () {
      final covered = {
        for (final t in fixture['Biology']!.take(32)) coverKey('Biology', t.topic),
      };
      expect(subjectProgress('Biology', fixture, covered).complete, isFalse);

      covered.add(coverKey('Biology', fixture['Biology']![32].topic));
      final p = subjectProgress('Biology', fixture, covered);
      expect(p.done, 33);
      expect(p.complete, isTrue);
      expect(p.fraction, 1);
    });

    test('does not call a subject with no notes complete', () {
      final p = subjectProgress('Yoruba', {'Yoruba': const []}, {});
      expect(p.total, 0);
      expect(p.done, 0);
      expect(p.complete, isFalse);
    });

    test('sums the whole plan', () {
      final covered = {
        for (final t in fixture['Biology']!) coverKey('Biology', t.topic),
      };
      final p = planProgress(subjects, fixture, covered);
      expect(p.done, 33);
      expect(p.total, 187);
      expect(p.complete, isFalse);
      expect(
        p.perSubject.firstWhere((s) => s.subject == 'Biology').complete,
        isTrue,
      );
    });

    test('matches coverage keys regardless of capitalisation or padding', () {
      final covered = {coverKey('Biology', '  bIoLoGy topic 1 ')};
      expect(subjectProgress('Biology', fixture, covered).done, 1);
    });
  });

  // ─── Selection ─────────────────────────────────────────────────────────────

  group('validateSelection', () {
    test('refuses fewer than $minPlanSubjects', () {
      expect(validateSelection(['a', 'b', 'c']), isNotNull);
    });

    test('refuses more than $maxPlanSubjects', () {
      expect(
        validateSelection(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']),
        isNotNull,
      );
    });

    test('accepts the boundaries', () {
      expect(validateSelection(['a', 'b', 'c', 'd']), isNull);
      expect(validateSelection(['a', 'b', 'c', 'd', 'e', 'f', 'g']), isNull);
    });

    test('counts a duplicated subject once', () {
      expect(validateSelection(['a', 'a', 'b', 'c']), isNotNull);
      expect(validateSelection(['a', 'a', 'b', 'c', 'd']), isNull);
    });
  });
}

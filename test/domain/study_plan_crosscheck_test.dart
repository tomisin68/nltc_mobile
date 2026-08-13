import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/study_plan.dart';

/// Dumps a long generated journey to disk so it can be diffed, byte for byte,
/// against the JavaScript original.
///
/// The app and the website both rebuild the week, and whichever the student
/// opens first that Monday writes it. If the two generators ever disagree, a
/// student sees one timetable on their phone and a different one in a browser
/// tab — and the bug surfaces as "my timetable changed by itself", which is
/// close to undebuggable from a support ticket. So they are compared directly.
///
/// The matching producer is src/tests/unit/studyPlan.crosscheck.test.js in the
/// website repo. Both are skipped unless NLTC_CROSSCHECK_DIR is set, so neither
/// writes files during an ordinary test run.
void main() {
  final outDir = Platform.environment['NLTC_CROSSCHECK_DIR'];

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
    'Short': topics('Short', 3),
  };

  String keyForIndex(int i) {
    final d = DateTime.utc(2024, 1, 1).add(Duration(days: i * 7));
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Every week of a journey, as flat strings — the exact thing to compare.
  List<String> journey(
    List<String> subjects,
    int weeks,
    String startKey,
    int skipEveryNth,
  ) {
    final covered = <String>{};
    final lines = <String>[];
    final start = weekIndexOf(startKey);

    for (var w = 0; w < weeks; w++) {
      final key = keyForIndex(start + w);
      final slots = buildWeek(
        subjects: subjects,
        topicsBySubject: fixture,
        covered: covered,
        weekStartKey: key,
      );
      for (final slot in slots) {
        lines.add(slot.rest
            ? '$key|${slot.day}|REST'
            : '$key|${slot.day}|${slot.subject}|${slot.topic}|${slot.noteId}');
        // A student who skips some weeks exercises the re-offer path too.
        if (!slot.rest && !(skipEveryNth != 0 && w % skipEveryNth == 0)) {
          covered.add(coverKey(slot.subject!, slot.topic!));
        }
      }
    }
    return lines;
  }

  final cases = [
    (
      name: '5 subjects, studied every week',
      subjects: ['Biology', 'Physics', 'Chemistry', 'Mathematics', 'Government'],
      weeks: 40,
      start: '2026-08-10',
      skip: 0,
    ),
    (
      name: '4 subjects, skipping every 3rd week',
      subjects: ['Biology', 'Physics', 'Chemistry', 'Mathematics'],
      weeks: 45,
      start: '2026-01-05',
      skip: 3,
    ),
    (
      name: '7 subjects incl. a very short one',
      subjects: ['Short', 'Biology', 'Physics', 'Chemistry', 'Mathematics', 'Government'],
      weeks: 40,
      start: '2025-12-29',
      skip: 0,
    ),
  ];

  test('writes the Dart side of the comparison', () {
    final out = cases
        .map((c) => [
              '## ${c.name}',
              ...journey(c.subjects, c.weeks, c.start, c.skip),
            ].join('\n'))
        .join('\n');

    Directory(outDir!).createSync(recursive: true);
    File('$outDir/dart-weeks.txt').writeAsStringSync('$out\n');
    expect(out, isNotEmpty);
  }, skip: outDir == null ? 'NLTC_CROSSCHECK_DIR not set' : false);
}

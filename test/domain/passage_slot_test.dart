import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/exam_config.dart';
import 'package:nltc/domain/models/passage_slot.dart';
import 'package:nltc/domain/models/question.dart';

/// One question, only as filled in as these tests need.
Question q(
  String id, {
  String? topic,
  String? passageId,
  int? passageOrder,
}) =>
    Question(
      id: id,
      subject: 'English Language',
      text: 'Question $id',
      options: const {'a': 'one', 'b': 'two'},
      answerKey: 'a',
      topic: topic,
      passageId: passageId,
      passageOrder: passageOrder,
    );

/// A passage's worth of questions, ids like `c1-0`.
List<Question> passage(String topic, String id, int length) => [
      for (var i = 0; i < length; i++)
        q('$id-$i', topic: topic, passageId: id, passageOrder: i),
    ];

/// Filler questions on ordinary topics.
List<Question> grammar(int n) =>
    [for (var i = 0; i < n; i++) q('g$i', topic: 'Tenses')];

/// The draw the assembler is given for everything outside the slots: takes the
/// first N, so the tests read deterministically.
List<Question> takeFirst(List<Question> pool, int count) =>
    pool.take(count).toList();

void main() {
  final slots = CbtExam.jambEnglishPassages;

  group('UTME English blueprint', () {
    test('comprehension is 1-5 and cloze is 16-25', () {
      expect(slots.length, 2);
      expect(slots.first.start, 0);
      expect(slots.first.length, 5);
      expect(slots.last.start, 15);
      expect(slots.last.length, 10);
    });
  });

  group('assemblePassagePaper', () {
    test('places one whole passage at each slot, in written order', () {
      final pool = [
        ...grammar(60),
        ...passage('Reading Comprehension', 'rc1', 5),
        ...passage('Cloze Test', 'cz1', 10),
      ];

      final paper = assemblePassagePaper(
        pool: pool,
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.length, 60);
      expect(
        paper.take(5).map((x) => x.id),
        ['rc1-0', 'rc1-1', 'rc1-2', 'rc1-3', 'rc1-4'],
      );
      expect(
        paper.sublist(15, 25).map((x) => x.id),
        [for (var i = 0; i < 10; i++) 'cz1-$i'],
      );
    });

    test('keeps a passage together even when the bank lists it jumbled', () {
      final scrambled = passage('Cloze Test', 'cz1', 10).reversed.toList();
      final paper = assemblePassagePaper(
        pool: [...grammar(60), ...scrambled],
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(
        paper.sublist(15, 25).map((x) => x.passageOrder),
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      );
    });

    test('every question comes from the same passage', () {
      final pool = [
        ...grammar(60),
        for (var p = 0; p < 6; p++) ...passage('Reading Comprehension', 'rc$p', 5),
        for (var p = 0; p < 4; p++) ...passage('Cloze Test', 'cz$p', 10),
      ];

      // Several draws, because picking one passage per slot is random.
      for (var run = 0; run < 25; run++) {
        final paper = assemblePassagePaper(
          pool: pool,
          count: 60,
          slots: slots,
          draw: takeFirst,
          random: Random(run),
        );
        expect(paper.take(5).map((x) => x.passageId).toSet().length, 1);
        expect(paper.sublist(15, 25).map((x) => x.passageId).toSet().length, 1);
      }
    });

    test('picks a different passage across sittings', () {
      final pool = [
        ...grammar(60),
        for (var p = 0; p < 8; p++) ...passage('Reading Comprehension', 'rc$p', 5),
      ];

      final seen = {
        for (var run = 0; run < 30; run++)
          assemblePassagePaper(
            pool: pool,
            count: 60,
            slots: slots,
            draw: takeFirst,
            random: Random(run),
          ).first.passageId,
      };

      expect(seen.length, greaterThan(1));
    });

    test('a passage question never appears outside its slot', () {
      final pool = [
        ...grammar(30),
        for (var p = 0; p < 4; p++) ...passage('Reading Comprehension', 'rc$p', 5),
        for (var p = 0; p < 4; p++) ...passage('Cloze Test', 'cz$p', 10),
      ];

      final paper = assemblePassagePaper(
        pool: pool,
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      for (var i = 0; i < paper.length; i++) {
        final inSlot = i < 5 || (i >= 15 && i < 25);
        expect(
          paper[i].passageId != null,
          inSlot,
          reason: 'question ${i + 1} is ${inSlot ? 'not ' : ''}from a passage',
        );
      }
    });

    test('no question is served twice', () {
      final pool = [
        ...grammar(60),
        ...passage('Reading Comprehension', 'rc1', 5),
        ...passage('Cloze Test', 'cz1', 10),
      ];
      final paper = assemblePassagePaper(
        pool: pool,
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.map((x) => x.id).toSet().length, paper.length);
    });

    test('skips a passage that is short of its full set', () {
      final pool = [
        ...grammar(60),
        ...passage('Reading Comprehension', 'short', 3),
        ...passage('Reading Comprehension', 'whole', 5),
      ];

      for (var run = 0; run < 20; run++) {
        final paper = assemblePassagePaper(
          pool: pool,
          count: 60,
          slots: slots,
          draw: takeFirst,
          random: Random(run),
        );
        expect(paper.first.passageId, 'whole');
      }
    });

    test('a bank with no passages still yields a full-length paper', () {
      final paper = assemblePassagePaper(
        pool: grammar(60),
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.length, 60);
      expect(paper.every((x) => x.passageId == null), isTrue);
    });

    test('one topic missing does not cost the other its passage', () {
      final paper = assemblePassagePaper(
        pool: [...grammar(60), ...passage('Cloze Test', 'cz1', 10)],
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.length, 60);
      expect(paper.take(5).every((x) => x.passageId == null), isTrue);
      expect(paper.sublist(15, 25).every((x) => x.passageId == 'cz1'), isTrue);
    });

    test('matches a topic the bank spells its own way', () {
      final paper = assemblePassagePaper(
        pool: [
          ...grammar(60),
          ...passage('Comprehension Passage', 'rc1', 5),
          ...passage('cloze test (passage 2)', 'cz1', 10),
        ],
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.take(5).every((x) => x.passageId == 'rc1'), isTrue);
      expect(paper.sublist(15, 25).every((x) => x.passageId == 'cz1'), isTrue);
    });

    test('a slot past the end of a short section is left alone', () {
      final paper = assemblePassagePaper(
        pool: [
          ...grammar(10),
          ...passage('Reading Comprehension', 'rc1', 5),
          ...passage('Cloze Test', 'cz1', 10),
        ],
        count: 10,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.length, 10);
      expect(paper.take(5).every((x) => x.passageId == 'rc1'), isTrue);
      expect(paper.skip(5).every((x) => x.passageId == null), isTrue);
    });

    test('runs short rather than repeating when the bank is thin', () {
      final paper = assemblePassagePaper(
        pool: [...grammar(20), ...passage('Reading Comprehension', 'rc1', 5)],
        count: 60,
        slots: slots,
        draw: takeFirst,
      );

      expect(paper.length, 25);
      expect(paper.map((x) => x.id).toSet().length, 25);
    });

    test('with no slots it is the plain draw', () {
      final pool = grammar(60);
      final paper = assemblePassagePaper(
        pool: pool,
        count: 40,
        slots: const [],
        draw: takeFirst,
      );

      expect(paper.map((x) => x.id), pool.take(40).map((x) => x.id));
    });
  });
}

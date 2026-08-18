import 'dart:math';

import 'question.dart';

/// A run of questions in a paper that all belong to one passage.
///
/// Comprehension and cloze questions are not questions on their own: each one
/// refers to a passage its neighbours share, so five of them drawn
/// independently would ask about five passages the student was shown none of.
/// A slot says "these positions in the section are one passage's worth of
/// questions", and the draw fills them as a group.
class PassageSlot {
  const PassageSlot({
    required this.topic,
    required this.keyword,
    required this.start,
    required this.length,
  });

  /// The topic these questions are filed under, spelled the way the bank
  /// spells it. Only the network draw uses this, as the value to query on.
  final String topic;

  /// How a question is recognised as belonging here: its topic, lower-cased,
  /// contains this. Deliberately looser than [topic] — a bank that says
  /// "Comprehension Passage" or "Cloze Test Passage" is still the same thing,
  /// and a paper is not worth losing to a spelling.
  final String keyword;

  /// 0-based position of the first question, counted within its own section.
  final int start;

  /// How many questions the passage supplies. A passage with fewer than this
  /// many rows in the bank is not usable and is passed over.
  final int length;

  bool claims(Question q) => (q.topic ?? '').toLowerCase().contains(keyword);
}

/// Builds one section of a paper with whole passages pinned in place.
///
/// Every slot is filled by the questions of a single randomly chosen passage,
/// in the order they were written; the positions between the slots are filled
/// by [draw] from everything else. A slot that cannot be filled — the passages
/// haven't been uploaded yet, or none has its full set of questions — takes
/// ordinary questions instead, so a bank with no passages in it still yields a
/// full-length paper rather than a short one.
///
/// Passage questions never leak into the gaps: one comprehension question
/// served among the grammar is a question about a passage nobody can see.
List<Question> assemblePassagePaper({
  required List<Question> pool,
  required int count,
  required List<PassageSlot> slots,
  required List<Question> Function(List<Question> pool, int count) draw,
  Random? random,
}) {
  if (slots.isEmpty || count <= 0) return draw(pool, count);

  final rng = random ?? Random();
  final pinned = <int, Question>{};

  for (final slot in slots) {
    if (slot.start >= count) continue; // the section is shorter than the paper
    final passage = _pickPassage(pool, slot, rng);
    if (passage == null) continue;
    for (var i = 0; i < passage.length && slot.start + i < count; i++) {
      pinned[slot.start + i] = passage[i];
    }
  }

  final taken = pinned.values.map((q) => q.id).toSet();
  final fillers = draw(
    pool
        .where((q) => !taken.contains(q.id) && !slots.any((s) => s.claims(q)))
        .toList(),
    count - pinned.length,
  );

  final paper = <Question>[];
  var next = 0;
  for (var i = 0; i < count; i++) {
    final held = pinned[i];
    if (held != null) {
      paper.add(held);
    } else if (next < fillers.length) {
      paper.add(fillers[next++]);
    }
  }
  return paper;
}

/// Whether [pool] already holds a whole passage for [slot] - every one of its
/// questions, under a single passage id.
///
/// A pool that doesn't is worth topping up from the bank before the paper is
/// assembled: a device that downloaded English before passages existed, or a
/// capped fetch that returned six of a cloze passage's ten questions, would
/// otherwise quietly serve a paper with no passage in it at all.
bool hasCompletePassage(Iterable<Question> pool, PassageSlot slot) =>
    _completePassages(pool, slot).isNotEmpty;

/// Every spelling this slot's questions are actually filed under in [pool].
///
/// [PassageSlot.topic] is what the network fetch asks Firestore for, and one
/// spelling is a thin thread to hang a paper on: a bank that files cloze under
/// "Cloze Test / Gap Filling" answers a query for "Cloze Test" with nothing,
/// and the slot falls back to ordinary questions without a word. Questions that
/// did arrive know the name they are filed under, so the fetch can ask for that
/// instead and survive the topic being renamed.
Set<String> passageTopicNames(Iterable<Question> pool, PassageSlot slot) {
  final names = <String>{};
  for (final q in pool) {
    if (!slot.claims(q)) continue;
    final topic = (q.topic ?? '').trim();
    if (topic.isNotEmpty) names.add(topic);
  }
  return names;
}

/// The passages in [pool] that have all of their questions.
///
/// A passage missing some is skipped rather than padded out: three questions on
/// a passage plus two on nothing is worse than five ordinary questions.
List<List<Question>> _completePassages(
  Iterable<Question> pool,
  PassageSlot slot,
) {
  final groups = <String, List<Question>>{};
  for (final q in pool) {
    final id = q.passageId;
    if (id == null || id.isEmpty || !slot.claims(q)) continue;
    groups.putIfAbsent(id, () => []).add(q);
  }
  return groups.values.where((g) => g.length >= slot.length).toList();
}

/// One complete passage's questions, in the order they were uploaded, or null
/// when the bank holds no complete one for this slot.
List<Question>? _pickPassage(
  List<Question> pool,
  PassageSlot slot,
  Random rng,
) {
  final complete = _completePassages(pool, slot);
  if (complete.isEmpty) return null;

  final chosen = [...complete[rng.nextInt(complete.length)]]
    ..sort((a, b) => (a.passageOrder ?? 0).compareTo(b.passageOrder ?? 0));
  return chosen.take(slot.length).toList();
}

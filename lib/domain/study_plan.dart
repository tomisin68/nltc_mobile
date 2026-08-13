/// The weekly study timetable: what it is, and the rules it is built by.
///
/// A student picks between four and seven subjects once. From then on, at the
/// start of every week, those subjects are laid across the seven days and each
/// day is given one topic to study — with a link straight into the study note
/// for it.
///
/// THE PROMISE THIS FILE KEEPS: a topic does not come round again until every
/// other topic in its subject has been covered. Not the next day, not in a later
/// week. That is what makes the timetable a route through a syllabus rather than
/// a shuffle, and it is why generation is a pure function of (subjects, topic
/// order, what has been covered, which week it is) with no randomness in it.
///
/// BOTH SURFACES REGENERATE. The app and the website each rebuild the week when
/// they notice the stored plan is for an older one, and whichever gets there
/// first writes it. So the two must land on identical weeks from identical
/// inputs, or a student would see one timetable on their phone and another in
/// the browser. This is a line-for-line port of `src/utils/studyPlan.js` in the
/// website repo for exactly that reason — change one, change the other.
library;

/// A student must pick at least this many subjects.
const int minPlanSubjects = 4;

/// And at most this many — one for each day of the week.
const int maxPlanSubjects = 7;

const int daysInWeek = 7;

const List<String> dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

const List<String> dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A Monday, used only as the origin for counting weeks.
///
/// 1 January 2024 was a Monday. Its single job is to turn a date into a stable
/// week number, so the rotation deciding which subject opens the week advances
/// by exactly one each week and agrees across devices.
final DateTime _epochMonday = DateTime.utc(2024, 1, 1);

/// One topic in a subject, as the backend's topic index returns it.
class PlanTopic {
  const PlanTopic({required this.id, required this.topic, this.order = 9999});

  final String id;
  final String topic;
  final int order;

  factory PlanTopic.fromJson(Map<String, dynamic> json) => PlanTopic(
        id: (json['id'] ?? '').toString(),
        topic: (json['topic'] ?? '').toString().trim(),
        order: (json['order'] as num?)?.toInt() ?? 9999,
      );
}

/// One day of the generated week.
class PlanSlot {
  const PlanSlot({
    required this.day,
    this.subject,
    this.topic,
    this.noteId,
    this.rest = false,
  });

  /// 0 = Monday.
  final int day;

  final String? subject;
  final String? topic;
  final String? noteId;

  /// Nothing left to study anywhere — see [buildWeek].
  final bool rest;

  factory PlanSlot.fromJson(Map<String, dynamic> json) => PlanSlot(
        day: (json['day'] as num?)?.toInt() ?? 0,
        subject: json['subject'] as String?,
        topic: json['topic'] as String?,
        noteId: json['noteId'] as String?,
        rest: json['rest'] == true,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'subject': subject,
        'topic': topic,
        'noteId': noteId,
        'rest': rest,
      };
}

// ─── Weeks ───────────────────────────────────────────────────────────────────

/// Midnight on the Monday of the week containing [date], in local time.
///
/// Local, not UTC: a student in Lagos starting their week on Monday morning
/// means Monday where they are. Built from calendar fields rather than by
/// subtracting a `Duration` so a week straddling a month or year boundary — or
/// a daylight-saving change, in a timezone that has one — still lands right.
DateTime mondayOf([DateTime? date]) {
  final now = date ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  // DateTime.monday is 1, so this is 0 on Monday and 6 on Sunday — and Sunday
  // belongs to the week that began six days earlier, not the one about to.
  final backTo = day.weekday - DateTime.monday;
  return DateTime(day.year, day.month, day.day - backTo);
}

/// The stable name of a week: the `YYYY-MM-DD` of its Monday.
///
/// Assembled from local calendar fields on purpose. `toIso8601String()` on a UTC
/// conversion would, west of Greenwich, report the previous day and file a
/// Monday under the Sunday before it.
String weekKey([DateTime? date]) {
  final monday = mondayOf(date);
  final mm = monday.month.toString().padLeft(2, '0');
  final dd = monday.day.toString().padLeft(2, '0');
  return '${monday.year}-$mm-$dd';
}

/// How many whole weeks a week key sits after the origin Monday.
int weekIndexOf(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return 0;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return 0;
  final days = DateTime.utc(y, m, d).difference(_epochMonday).inDays;
  return (days / 7).floor();
}

/// The date of day [i] (0 = Monday) in the week named by [key].
DateTime dayOfWeekKey(String key, int i) {
  final parts = key.split('-');
  if (parts.length != 3) return DateTime.now();
  return DateTime(
    int.tryParse(parts[0]) ?? 2024,
    int.tryParse(parts[1]) ?? 1,
    (int.tryParse(parts[2]) ?? 1) + i,
  );
}

// ─── Coverage ────────────────────────────────────────────────────────────────

/// The key under which "this student has studied this topic" is recorded.
///
/// Case- and space-insensitive, because a topic title is typed by hand in the
/// admin screen and the same topic can pick up stray capitalisation between one
/// upload and the next. Coverage has to survive that; if it did not, a retyped
/// topic would quietly come round again and break the promise at the top.
String coverKey(String subject, String topic) =>
    '${subject.trim().toLowerCase()}::${topic.trim().toLowerCase()}';

/// How far through a subject the student is.
class SubjectProgress {
  const SubjectProgress({
    required this.subject,
    required this.done,
    required this.total,
  });

  final String subject;
  final int done;
  final int total;

  /// A subject with no notes yet is not "complete" — there is simply nothing
  /// there, and calling that finished would be a lie the progress bar tells.
  bool get complete => total > 0 && done >= total;

  double get fraction => total > 0 ? done / total : 0;
}

SubjectProgress subjectProgress(
  String subject,
  Map<String, List<PlanTopic>> topicsBySubject,
  Set<String> covered,
) {
  final topics = topicsBySubject[subject] ?? const <PlanTopic>[];
  final done =
      topics.where((t) => covered.contains(coverKey(subject, t.topic))).length;
  return SubjectProgress(subject: subject, done: done, total: topics.length);
}

/// Every chosen subject's progress, plus the totals under it.
class PlanProgress {
  const PlanProgress({required this.perSubject, required this.done, required this.total});

  final List<SubjectProgress> perSubject;
  final int done;
  final int total;

  bool get complete => total > 0 && done >= total;
  double get fraction => total > 0 ? done / total : 0;
}

PlanProgress planProgress(
  List<String> subjects,
  Map<String, List<PlanTopic>> topicsBySubject,
  Set<String> covered,
) {
  final per = [
    for (final s in subjects) subjectProgress(s, topicsBySubject, covered),
  ];
  return PlanProgress(
    perSubject: per,
    done: per.fold(0, (n, p) => n + p.done),
    total: per.fold(0, (n, p) => n + p.total),
  );
}

// ─── Generating a week ───────────────────────────────────────────────────────

/// Lays one week out: seven days, each with a subject and the topic to study.
///
/// The rotation. Subjects are dealt round the seven days from an offset that
/// advances by one each week, so a student with five subjects does not open
/// every Monday on the same one. With seven subjects each gets a day; with four,
/// three come round twice — but on different topics, because a subject's topics
/// are drawn from a queue consumed as the week is built.
///
/// The queue holds only topics not yet covered, in the server's order. That is
/// the whole of the no-repeat guarantee: a covered topic is never a candidate
/// again, and an uncovered one is offered in sequence until it is studied.
///
/// When a subject runs out — every topic in it covered — its day goes to another
/// subject that still has something left, rather than being wasted. A day only
/// becomes a rest day once there is nothing left to study in any of them.
List<PlanSlot> buildWeek({
  required List<String> subjects,
  required Map<String, List<PlanTopic>> topicsBySubject,
  required Set<String> covered,
  required String weekStartKey,
}) {
  final chosen = subjects.where((s) => s.trim().isNotEmpty).toList();
  if (chosen.isEmpty) return const [];

  // One cursor per subject, walking its uncovered topics in order.
  final queues = <String, List<PlanTopic>>{};
  final cursor = <String, int>{};
  for (final subject in chosen) {
    queues[subject] = (topicsBySubject[subject] ?? const <PlanTopic>[])
        .where((t) => !covered.contains(coverKey(subject, t.topic)))
        .toList();
    cursor[subject] = 0;
  }

  final offset =
      ((weekIndexOf(weekStartKey) % chosen.length) + chosen.length) % chosen.length;
  final slots = <PlanSlot>[];

  for (var day = 0; day < daysInWeek; day++) {
    final preferred = chosen[(day + offset) % chosen.length];
    final previous = day > 0 ? slots[day - 1].subject : null;

    final subject = _pickSubject(chosen, preferred, previous, queues, cursor);
    if (subject == null) {
      // Nothing uncovered left anywhere. The student has finished the syllabus
      // they signed up for, so the rest of the week says so rather than
      // inventing filler.
      slots.add(PlanSlot(day: day, rest: true));
      continue;
    }

    final next = queues[subject]![cursor[subject]!];
    cursor[subject] = cursor[subject]! + 1;
    slots.add(PlanSlot(
      day: day,
      subject: subject,
      topic: next.topic,
      noteId: next.id.isEmpty ? null : next.id,
    ));
  }

  return slots;
}

/// Which subject gets this day.
///
/// The one whose turn it is, if it still has an unstudied topic in hand.
/// Otherwise the next one round the rotation that does — skipping, where it can,
/// whatever filled yesterday, so a fallback never puts the same subject on two
/// days running.
String? _pickSubject(
  List<String> chosen,
  String preferred,
  String? previous,
  Map<String, List<PlanTopic>> queues,
  Map<String, int> cursor,
) {
  bool hasTopic(String s) => cursor[s]! < queues[s]!.length;
  if (hasTopic(preferred)) return preferred;

  final from = chosen.indexOf(preferred);
  final rotated = [
    for (var i = 1; i <= chosen.length; i++) chosen[(from + i) % chosen.length],
  ];

  final available = rotated.where(hasTopic).toList();
  if (available.isEmpty) return null;
  return available.firstWhere((s) => s != previous, orElse: () => available.first);
}

// ─── The stored plan ─────────────────────────────────────────────────────────

/// Whether a subject selection is allowed to be saved.
///
/// The maximum is seven because the week has seven days and an eighth subject
/// would never be scheduled. The minimum of four is the point below which the
/// same few subjects repeat so often the week stops looking like a timetable.
String? validateSelection(List<String> subjects) {
  final unique = subjects.where((s) => s.trim().isNotEmpty).toSet();
  if (unique.length < minPlanSubjects) {
    return 'Pick at least $minPlanSubjects subjects.';
  }
  if (unique.length > maxPlanSubjects) {
    return 'Pick no more than $maxPlanSubjects subjects.';
  }
  return null;
}

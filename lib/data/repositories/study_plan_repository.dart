import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/study_plan.dart';
import '../services/api_client.dart';

/// One student's saved weekly timetable.
class StudyPlan {
  const StudyPlan({
    required this.subjects,
    required this.weekOf,
    required this.slots,
    required this.covered,
  });

  final List<String> subjects;

  /// The `YYYY-MM-DD` Monday the stored week belongs to.
  final String weekOf;

  final List<PlanSlot> slots;

  /// Composite `subject::topic` keys — see [coverKey].
  final Set<String> covered;

  bool get hasSubjects => subjects.isNotEmpty;

  /// Whether the stored week has been overtaken by the calendar.
  bool isStale(String currentWeek) => weekOf != currentWeek || slots.isEmpty;

  static const empty = StudyPlan(
    subjects: [],
    weekOf: '',
    slots: [],
    covered: {},
  );

  StudyPlan copyWith({
    List<String>? subjects,
    String? weekOf,
    List<PlanSlot>? slots,
    Set<String>? covered,
  }) =>
      StudyPlan(
        subjects: subjects ?? this.subjects,
        weekOf: weekOf ?? this.weekOf,
        slots: slots ?? this.slots,
        covered: covered ?? this.covered,
      );

  factory StudyPlan.fromMap(Map<String, dynamic> data) => StudyPlan(
        subjects: [
          for (final s in (data['subjects'] as List?) ?? const [])
            if (s is String && s.trim().isNotEmpty) s,
        ],
        weekOf: (data['weekOf'] as String?) ?? '',
        slots: [
          for (final s in (data['slots'] as List?) ?? const [])
            if (s is Map) PlanSlot.fromJson(Map<String, dynamic>.from(s)),
        ],
        covered: {
          for (final c in (data['covered'] as List?) ?? const [])
            if (c is String) c,
        },
      );

  Map<String, dynamic> toMap() => {
        'subjects': subjects,
        'weekOf': weekOf,
        'slots': [for (final s in slots) s.toJson()],
        'covered': covered.toList(),
      };
}

/// Reads and writes `studyPlans/{uid}`, and fetches the syllabus behind it.
///
/// The document id IS the student's uid, which makes "one plan per student" a
/// property of the data rather than a rule somebody has to remember to check.
/// It is private to its owner both ways: a plan says exactly which subjects a
/// student is weak enough to be revising and how little of each they have got
/// through, which is nobody else's business.
class StudyPlanRepository {
  StudyPlanRepository({required ApiClient api, FirebaseFirestore? firestore})
      : _api = api,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('studyPlans').doc(uid);

  /// Every topic that has a study note, grouped by subject.
  ///
  /// This goes through the backend rather than reading `studyNotes` directly,
  /// and that is not an arbitrary choice. A note's `content` is a whole HTML
  /// page — its own stylesheet, tables, inline SVG diagrams — and there are
  /// hundreds of them. Reading the collection to list four hundred titles would
  /// pull megabytes of markup down a phone connection. The endpoint uses the
  /// Admin SDK's field mask, which the client SDK has no equivalent of, so
  /// `content` never leaves the database.
  ///
  /// The server also fixes the topic ORDER. The no-repeat promise is a promise
  /// about a sequence, and it only holds if the app and the browser walk the
  /// same one — so neither of them gets to decide it.
  Future<Map<String, List<PlanTopic>>> syllabus(String category) async {
    final data = await _api.get('/study-notes/topics', query: {'category': category});
    final entries = (data['subjects'] as List?) ?? const [];

    final map = <String, List<PlanTopic>>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final subject = (entry['subject'] ?? '').toString().trim();
      if (subject.isEmpty) continue;
      map[subject] = [
        for (final t in (entry['topics'] as List?) ?? const [])
          if (t is Map) PlanTopic.fromJson(Map<String, dynamic>.from(t)),
      ];
    }
    return map;
  }

  /// This student's plan, or [StudyPlan.empty] if they have never built one.
  ///
  /// Returns empty rather than throwing: every caller treats "no plan" and
  /// "could not tell" the same way — both mean showing the subject picker — and
  /// a timetable that refuses to open because Firestore was slow helps nobody.
  Future<StudyPlan> mine(String uid) async {
    if (uid.isEmpty) return StudyPlan.empty;
    try {
      final snap = await _doc(uid).get();
      final data = snap.data();
      if (data == null) return StudyPlan.empty;
      return StudyPlan.fromMap(data);
    } catch (_) {
      return StudyPlan.empty;
    }
  }

  Future<void> save(String uid, StudyPlan plan, {required String category}) =>
      _doc(uid).set({
        ...plan.toMap(),
        'uid': uid,
        'category': category,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart' show tsToMs;
import '../../domain/models/question.dart';
import '../services/api_client.dart';
import '../services/firestore_cache.dart';

/// How often a question has been served to this student, and when last.
class SeenQuestion {
  const SeenQuestion({required this.seenCount, required this.lastSeenAt});

  final int seenCount;
  final int lastSeenAt;

  static const unseen = SeenQuestion(seenCount: 0, lastSeenAt: 0);

  factory SeenQuestion.fromMap(Map<String, dynamic> m) => SeenQuestion(
        seenCount: m['seenCount'] is num ? (m['seenCount'] as num).toInt() : 0,
        lastSeenAt: tsToMs(m['lastSeenAt']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'seenCount': seenCount,
        'lastSeenAt': lastSeenAt,
      };
}

/// A topic the engine thinks this student is weak on.
class WeakTopic {
  const WeakTopic({
    required this.subject,
    required this.topic,
    required this.mastery,
  });

  /// The slugified subject key — `further_mathematics`, not the display name.
  final String subject;
  final String topic;

  /// 0..1.
  final double mastery;

  /// `further_mathematics` → `Further Mathematics`, for display.
  String get subjectLabel => subject
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  factory WeakTopic.fromMap(Map<String, dynamic> m) => WeakTopic(
        subject: (m['subject'] ?? '').toString(),
        topic: (m['topic'] ?? '').toString(),
        mastery: m['pMastery'] is num ? (m['pMastery'] as num).toDouble() : 0,
      );

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'topic': topic,
        'pMastery': mastery,
      };
}

/// The student's adaptive-learning profile (`users/{uid}/ml/profile`).
class LearningProfile {
  const LearningProfile({
    this.abilityBySubject = const {},
    this.seenQuestions = const {},
    this.weakTopics = const [],
  });

  /// Elo rating per subject key. 1200 is the neutral starting point.
  final Map<String, double> abilityBySubject;

  final Map<String, SeenQuestion> seenQuestions;
  final List<WeakTopic> weakTopics;

  static const neutralTheta = 1200.0;

  double thetaFor(String subjectKey) =>
      abilityBySubject[subjectKey] ?? neutralTheta;

  factory LearningProfile.fromMap(Map<String, dynamic> m) {
    final ability = <String, double>{};
    final rawAbility = m['abilityBySubject'];
    if (rawAbility is Map) {
      rawAbility.forEach((key, value) {
        final theta = value is Map ? value['theta'] : null;
        if (theta is num) ability[key.toString()] = theta.toDouble();
      });
    }

    final seen = <String, SeenQuestion>{};
    final rawSeen = m['seenQuestions'];
    if (rawSeen is Map) {
      rawSeen.forEach((key, value) {
        if (value is Map) {
          seen[key.toString()] =
              SeenQuestion.fromMap(Map<String, dynamic>.from(value));
        }
      });
    }

    final weak = <WeakTopic>[];
    final rawWeak = m['weakTopics'];
    if (rawWeak is List) {
      for (final row in rawWeak) {
        if (row is Map) {
          weak.add(WeakTopic.fromMap(Map<String, dynamic>.from(row)));
        }
      }
    }

    return LearningProfile(
      abilityBySubject: ability,
      seenQuestions: seen,
      weakTopics: weak,
    );
  }

  Map<String, dynamic> toJson() => {
        'abilityBySubject': {
          for (final entry in abilityBySubject.entries)
            entry.key: {'theta': entry.value},
        },
        'seenQuestions': {
          for (final entry in seenQuestions.entries)
            entry.key: entry.value.toJson(),
        },
        'weakTopics': [for (final t in weakTopics) t.toJson()],
      };
}

/// One answered question, on its way to the learning engine.
class AnswerRecord {
  const AnswerRecord({
    required this.questionId,
    required this.subject,
    required this.correct,
    this.topic,
    this.difficultyLabel,
  });

  final String questionId;

  /// The subject *key*, not the display name — the engine indexes ability by key.
  final String subject;
  final bool correct;
  final String? topic;
  final String? difficultyLabel;

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'subject': subject,
        'correct': correct,
        'topic': topic,
        'difficultyLabel': difficultyLabel,
      };
}

/// Reads the adaptive profile and posts answers back to it.
///
/// The ranking in [rankByFit] is the app's half of the same contract the web
/// implements in `CBTPage.jsx`: the two must agree, or a student would be served
/// questions they have just done on the website. Cached under the same key the
/// web uses so a session started in either place sees the same ability estimate.
class LearningProfileRepository {
  LearningProfileRepository({
    required ApiClient api,
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
  })  : _api = api,
        _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  static String cacheKeyFor(String uid) => 'mlprofile_$uid';

  /// Seed ratings for questions the engine has not rated yet, taken from the
  /// admin's difficulty label. Same numbers as `DIFFICULTY_SEED_RATING` on the web.
  static const _difficultySeed = <String, double>{
    'easy': 1000,
    'medium': 1200,
    'hard': 1400,
  };

  Future<LearningProfile> load(String? uid) async {
    if (uid == null || uid.isEmpty) return const LearningProfile();

    return _cache.read<LearningProfile>(
      cacheKeyFor(uid),
      CacheTtl.quickTests,
      () async {
        try {
          final snap = await _db
              .collection('users')
              .doc(uid)
              .collection('ml')
              .doc('profile')
              .get();
          return LearningProfile.fromMap(snap.data() ?? const {});
        } catch (_) {
          // Offline, or the doc has never been written. A neutral profile ranks
          // purely on freshness, which is still better than a blind shuffle.
          return const LearningProfile();
        }
      },
      decode: (json) => LearningProfile.fromMap(
        json is Map ? Map<String, dynamic>.from(json) : const {},
      ),
    );
  }

  /// Orders [pool] by how well each question fits this student right now.
  ///
  /// Unseen questions come first, so the bank isn't repeated until it's
  /// exhausted; within a freshness tier the question whose Elo rating sits
  /// closest to the student's ability wins, which is the "productive struggle"
  /// target adaptive testing aims for. Ties break on how long ago the question
  /// was last served, then randomly so two identical sittings still differ.
  ///
  /// A direct port of `rankByFit` in `src/pages/CBTPage.jsx`.
  static List<Question> rankByFit(
    List<Question> pool,
    double theta,
    Map<String, SeenQuestion> seen,
  ) {
    final ranked = [...pool];
    final jitter = <String, double>{
      for (final q in pool) q.id: _random.nextDouble(),
    };

    ranked.sort((a, b) {
      final seenA = seen[a.id] ?? SeenQuestion.unseen;
      final seenB = seen[b.id] ?? SeenQuestion.unseen;

      final byFreshness = seenA.seenCount.compareTo(seenB.seenCount);
      if (byFreshness != 0) return byFreshness;

      final byFit = _gap(a, theta).compareTo(_gap(b, theta));
      if (byFit != 0) return byFit;

      final byAge = seenA.lastSeenAt.compareTo(seenB.lastSeenAt);
      if (byAge != 0) return byAge;

      return (jitter[a.id] ?? 0).compareTo(jitter[b.id] ?? 0);
    });
    return ranked;
  }

  static double _gap(Question q, double theta) {
    final rating = q.eloRating ??
        _difficultySeed[(q.difficulty ?? '').toLowerCase()] ??
        LearningProfile.neutralTheta;
    return (rating - theta).abs();
  }

  static final _random = Random();

  /// Sends a finished sitting's per-question results to the learning engine.
  ///
  /// Best-effort: the sitting is already scored and saved by the time this runs,
  /// and a student on a bad connection must not see an error for it. The cached
  /// profile is dropped on success so the next sitting sees the updated
  /// seen-question map.
  Future<void> recordAnswers(String uid, List<AnswerRecord> answers) async {
    if (answers.isEmpty) return;
    try {
      await _api.post('/cbt/record-answers', {
        'answers': [for (final a in answers) a.toJson()],
      });
      _cache.invalidate(cacheKeyFor(uid));
      _cache.invalidate('mlProfile_$uid');
      _cache.invalidate('subjectCoverage_${uid}_questions');
      _cache.invalidate('subjectCoverage_${uid}_jssQuestions');
    } catch (_) {
      // The raw log is the engine's durable record; losing one batch costs a
      // little adaptivity, not a result.
    }
  }
}

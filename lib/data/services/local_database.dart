import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/exam_attempt.dart';
import '../../domain/models/question.dart';

/// On-device SQLite store — the reason the app works with no signal.
///
/// Holds three things:
///   • downloaded question banks, per subject
///   • finished exam attempts, including ones still waiting to sync
///   • the notification inbox
///
/// Firestore's own persistence covers documents the student has already read;
/// this database covers the things we deliberately pre-download and the writes
/// that must outlive a failed request.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;
  static LocalDatabase? _instance;

  static const _fileName = 'nltc_offline.db';

  /// v2 added the two columns adaptive selection and diagram questions need.
  static const _version = 2;

  static Future<LocalDatabase> open() async {
    if (_instance != null) return _instance!;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _fileName),
      version: _version,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    return _instance = LocalDatabase._(db);
  }

  /// Adds columns in place rather than dropping the table: a student who has
  /// downloaded four subject banks over mobile data must not lose them to an
  /// app update. The new columns come back null on existing rows, which both
  /// readers already treat as "not set".
  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE questions ADD COLUMN image_url TEXT');
      await db.execute('ALTER TABLE questions ADD COLUMN elo_rating REAL');
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE questions (
        id          TEXT PRIMARY KEY,
        subject     TEXT NOT NULL,
        text        TEXT NOT NULL,
        options     TEXT NOT NULL,
        answer_key  TEXT NOT NULL,
        topic       TEXT,
        year        INTEGER,
        explanation TEXT,
        exam_type   TEXT,
        difficulty  TEXT,
        image_url   TEXT,
        elo_rating  REAL
      )
    ''');
    // Every question read is scoped by subject, and most also by topic.
    await db.execute(
      'CREATE INDEX idx_questions_subject ON questions (subject)',
    );
    await db.execute(
      'CREATE INDEX idx_questions_subject_topic ON questions (subject, topic)',
    );

    // One row per downloaded subject, so the UI can show what's available
    // offline and when it was last refreshed.
    await db.execute('''
      CREATE TABLE subject_packs (
        subject        TEXT PRIMARY KEY,
        question_count INTEGER NOT NULL DEFAULT 0,
        downloaded_at  INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attempts (
        id               TEXT PRIMARY KEY,
        subject          TEXT NOT NULL,
        exam             TEXT NOT NULL,
        topic            TEXT,
        question_ids     TEXT NOT NULL,
        answers          TEXT NOT NULL,
        correct          INTEGER NOT NULL,
        total            INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        submitted_at     INTEGER NOT NULL,
        sync_state       TEXT NOT NULL,
        sync_attempts    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_attempts_sync ON attempts (sync_state, submitted_at)',
    );

    await db.execute('''
      CREATE TABLE notifications (
        id         TEXT PRIMARY KEY,
        title      TEXT NOT NULL,
        body       TEXT NOT NULL,
        category   TEXT,
        route      TEXT,
        created_at INTEGER NOT NULL,
        read       INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_notifications_created ON notifications (created_at DESC)',
    );
  }

  // ─── Question banks ──────────────────────────────────────────────────────

  /// Replaces a subject's bank in one transaction, so an interrupted download
  /// can never leave a half-written pack that looks complete.
  Future<void> saveSubjectPack(String subject, List<Question> questions) async {
    await _db.transaction((txn) async {
      await txn.delete('questions', where: 'subject = ?', whereArgs: [subject]);

      final batch = txn.batch();
      for (final q in questions) {
        batch.insert(
          'questions',
          q.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      batch.insert(
        'subject_packs',
        {
          'subject': subject,
          'question_count': questions.length,
          'downloaded_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteSubjectPack(String subject) async {
    await _db.transaction((txn) async {
      await txn.delete('questions', where: 'subject = ?', whereArgs: [subject]);
      await txn
          .delete('subject_packs', where: 'subject = ?', whereArgs: [subject]);
    });
  }

  Future<List<SubjectPack>> downloadedPacks() async {
    final rows = await _db.query('subject_packs', orderBy: 'subject ASC');
    return rows.map(SubjectPack.fromRow).toList();
  }

  Future<SubjectPack?> packFor(String subject) async {
    final rows = await _db.query(
      'subject_packs',
      where: 'subject = ?',
      whereArgs: [subject],
      limit: 1,
    );
    return rows.isEmpty ? null : SubjectPack.fromRow(rows.first);
  }

  /// Pulls a random selection for an exam. `ORDER BY RANDOM()` is fine at this
  /// scale (a few thousand rows per subject) and keeps selection in SQLite
  /// rather than loading the whole bank into memory to shuffle it.
  Future<List<Question>> drawQuestions({
    required String subject,
    required int count,
    String? topic,
  }) async {
    final rows = await _db.query(
      'questions',
      where: topic == null ? 'subject = ?' : 'subject = ? AND topic = ?',
      whereArgs: topic == null ? [subject] : [subject, topic],
      orderBy: 'RANDOM()',
      limit: count,
    );
    return rows.map(Question.fromRow).where((q) => q.isUsable).toList();
  }

  /// The whole candidate pool for a sitting, unordered.
  ///
  /// Distinct from [drawQuestions], which lets SQLite pick at random. Adaptive
  /// selection has to see every candidate before it can rank them by fit, so the
  /// filtering happens here and the ordering happens in Dart.
  Future<List<Question>> questionPool({
    required String subject,
    List<String> topics = const [],
    String? examType,
    String? difficulty,
    int limit = 3000,
  }) async {
    final clauses = <String>['subject = ?'];
    final args = <Object?>[subject];

    if (topics.isNotEmpty) {
      clauses.add('topic IN (${List.filled(topics.length, '?').join(',')})');
      args.addAll(topics);
    }
    // Matched case-insensitively: the admin uploader writes "utme" and "UTME"
    // into the same column, and the web compares lower-cased for the same reason.
    if (examType != null && examType.isNotEmpty) {
      clauses.add('LOWER(exam_type) = ?');
      args.add(examType.toLowerCase());
    }
    if (difficulty != null && difficulty.isNotEmpty) {
      clauses.add('LOWER(difficulty) = ?');
      args.add(difficulty.toLowerCase());
    }

    final rows = await _db.query(
      'questions',
      where: clauses.join(' AND '),
      whereArgs: args,
      limit: limit,
    );
    return rows.map(Question.fromRow).where((q) => q.isUsable).toList();
  }

  /// Distinct exam types and difficulty labels present in a downloaded bank —
  /// what the topic-mode filters offer.
  Future<List<String>> distinctValues(String subject, String column) async {
    if (!const {'exam_type', 'difficulty'}.contains(column)) {
      throw ArgumentError.value(column, 'column', 'not a filterable column');
    }
    final rows = await _db.rawQuery(
      'SELECT DISTINCT $column AS v FROM questions '
      "WHERE subject = ? AND $column IS NOT NULL AND $column != '' "
      'ORDER BY v ASC',
      [subject],
    );
    return rows.map((r) => r['v'] as String).toList();
  }

  Future<List<Question>> questionsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.query(
      'questions',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final byId = {for (final r in rows) r['id'] as String: Question.fromRow(r)};
    // Preserve the original order the student saw.
    return ids.map((id) => byId[id]).whereType<Question>().toList();
  }

  Future<List<String>> topicsFor(String subject) async {
    final rows = await _db.rawQuery(
      "SELECT DISTINCT topic FROM questions WHERE subject = ? AND topic IS NOT NULL AND topic != '' ORDER BY topic ASC",
      [subject],
    );
    return rows.map((r) => r['topic'] as String).toList();
  }

  // ─── Attempts ────────────────────────────────────────────────────────────

  Future<void> saveAttempt(ExamAttempt attempt) async {
    await _db.insert(
      'attempts',
      attempt.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ExamAttempt>> recentAttempts({int limit = 30}) async {
    final rows = await _db.query(
      'attempts',
      orderBy: 'submitted_at DESC',
      limit: limit,
    );
    return rows.map(ExamAttempt.fromRow).toList();
  }

  /// Oldest first — attempts should reach the server in the order they happened.
  Future<List<ExamAttempt>> unsyncedAttempts() async {
    final rows = await _db.query(
      'attempts',
      where: 'sync_state != ?',
      whereArgs: [SyncState.synced.name],
      orderBy: 'submitted_at ASC',
    );
    return rows.map(ExamAttempt.fromRow).toList();
  }

  Future<int> unsyncedCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM attempts WHERE sync_state != ?',
      [SyncState.synced.name],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> markAttemptSync(
    String id,
    SyncState state, {
    int? syncAttempts,
  }) async {
    await _db.update(
      'attempts',
      {
        'sync_state': state.name,
        'sync_attempts': ?syncAttempts,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Notifications ───────────────────────────────────────────────────────

  Future<void> saveNotification(Map<String, Object?> row) async {
    await _db.insert(
      'notifications',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveNotifications(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.batch();
    for (final row in rows) {
      batch.insert(
        'notifications',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> notifications({int limit = 50}) =>
      _db.query('notifications', orderBy: 'created_at DESC', limit: limit);

  /// Ids the student has already opened. A refresh from the server must not
  /// resurrect an unread badge for something they read while offline — reads
  /// only ever travel one way.
  Future<Set<String>> readNotificationIds() async {
    final rows = await _db.query(
      'notifications',
      columns: ['id'],
      where: 'read = 1',
    );
    return rows.map((r) => r['id'] as String).toSet();
  }

  Future<int> unreadNotificationCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM notifications WHERE read = 0',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(String id) async {
    await _db.update('notifications', {'read': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAllNotificationsRead() async {
    await _db.update('notifications', {'read': 1}, where: 'read = 0');
  }

  /// Wipes everything student-specific. Called on sign-out so a shared phone
  /// never leaks one student's attempts to the next.
  Future<void> clearUserData() async {
    await _db.transaction((txn) async {
      await txn.delete('attempts');
      await txn.delete('notifications');
    });
  }
}

/// Summary of one downloaded subject bank.
class SubjectPack {
  const SubjectPack({
    required this.subject,
    required this.questionCount,
    required this.downloadedAt,
  });

  final String subject;
  final int questionCount;
  final DateTime downloadedAt;

  factory SubjectPack.fromRow(Map<String, Object?> r) => SubjectPack(
        subject: r['subject'] as String,
        questionCount: (r['question_count'] as num?)?.toInt() ?? 0,
        downloadedAt: DateTime.fromMillisecondsSinceEpoch(
          (r['downloaded_at'] as num?)?.toInt() ?? 0,
        ),
      );

  /// Banks older than a fortnight are worth refreshing when there's signal.
  bool get isStale =>
      DateTime.now().difference(downloadedAt) > const Duration(days: 14);
}

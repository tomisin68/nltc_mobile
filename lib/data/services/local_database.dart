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
  /// v3 added the staging table a download of any size writes through.
  /// v4 added the two columns that keep a comprehension or cloze passage
  /// together — which passage a question belongs to, and where it sits in it.
  static const _version = 4;

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
    if (oldVersion < 3) {
      await db.execute(_stagingTable);
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE questions ADD COLUMN passage_id TEXT');
      await db.execute('ALTER TABLE questions ADD COLUMN passage_order INTEGER');
      // Staging holds nothing between downloads, so it is rebuilt rather than
      // migrated. Existing packs keep their questions and simply have no
      // passages until the subject is downloaded again.
      await db.execute('DROP TABLE IF EXISTS questions_staging');
      await db.execute(_stagingTable);
    }
  }

  /// Where a download lands while it is still arriving.
  ///
  /// A pack has to be committed all at once — a half-written one that looks
  /// complete is worse than no pack at all — but a whole bank is too much to
  /// hold in memory on a cheap phone while it downloads. Pages are written here
  /// as they arrive and swapped into `questions` in a single transaction at the
  /// end, which buys both. No indexes: nothing ever queries this table, it is
  /// only filled, copied out, and emptied.
  static const _stagingTable = '''
    CREATE TABLE IF NOT EXISTS questions_staging (
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
      elo_rating  REAL,
      passage_id  TEXT,
      passage_order INTEGER
    )
  ''';

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
        elo_rating  REAL,
        passage_id  TEXT,
        passage_order INTEGER
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

    await db.execute(_stagingTable);
  }

  // ─── Question banks ──────────────────────────────────────────────────────

  /// Starts a download, throwing away anything a previous one left behind.
  ///
  /// Staging is deliberately not per-subject: only one download runs at a time,
  /// and a leftover half-pack from a download that was killed mid-flight has no
  /// value to anyone.
  Future<void> beginSubjectPack() => _db.delete('questions_staging');

  /// Writes one page of a download to disk. Returns the running total, counted
  /// in the table rather than by the caller so a question that arrives twice
  /// across two pages is not counted twice.
  Future<int> stageQuestions(List<Question> questions) async {
    if (questions.isNotEmpty) {
      final batch = _db.batch();
      for (final q in questions) {
        batch.insert(
          'questions_staging',
          q.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
    return stagedCount();
  }

  /// How many questions the download in flight has written so far.
  Future<int> stagedCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM questions_staging',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Swaps a finished download into place, replacing the subject's previous bank
  /// in one transaction — so an interrupted download can never leave a
  /// half-written pack that looks complete. Returns how many were committed.
  Future<int> commitSubjectPack(String subject) async {
    final count = await stagedCount();
    await _db.transaction((txn) async {
      await txn.delete('questions', where: 'subject = ?', whereArgs: [subject]);
      await txn.execute(
        'INSERT OR REPLACE INTO questions '
        '(id, subject, text, options, answer_key, topic, year, explanation, '
        ' exam_type, difficulty, image_url, elo_rating, passage_id, '
        ' passage_order) '
        'SELECT id, ?, text, options, answer_key, topic, year, explanation, '
        '       exam_type, difficulty, image_url, elo_rating, passage_id, '
        '       passage_order '
        'FROM questions_staging',
        [subject],
      );
      await txn.delete('questions_staging');
      await txn.insert(
        'subject_packs',
        {
          'subject': subject,
          'question_count': count,
          'downloaded_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return count;
  }

  /// Drops a download that failed part-way. The previous pack, if there was one,
  /// is untouched and still usable.
  Future<void> discardStagedPack() async {
    try {
      await _db.delete('questions_staging');
    } catch (_) {
      // Nothing to clean up, or the database is already closed. Either way the
      // next download clears the table before it starts.
    }
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

  /// The candidate pool for a sitting.
  ///
  /// Distinct from [drawQuestions], which asks SQLite for the finished exam. The
  /// draw has to see the candidates before it can hold back the ones this
  /// student has already been served, so filtering happens here and the choosing
  /// happens in Dart.
  ///
  /// [limit] only bounds how much of a bank is held in memory at once; a subject
  /// with more questions than that is sampled at random rather than cut off at
  /// the first N rows, because SQLite's natural order is insertion order — a
  /// plain limit would mean the questions uploaded last were never once served.
  Future<List<Question>> questionPool({
    required String subject,
    List<String> topics = const [],
    String? examType,
    int limit = 6000,
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

    final rows = await _db.query(
      'questions',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'RANDOM()',
      limit: limit,
    );
    return rows.map(Question.fromRow).where((q) => q.isUsable).toList();
  }

  /// Distinct exam types present in a downloaded bank — what the topic-mode
  /// filter offers. `difficulty` is stored but deliberately not filterable:
  /// the labels were never applied consistently enough to mean anything.
  Future<List<String>> distinctValues(String subject, String column) async {
    if (!const {'exam_type'}.contains(column)) {
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

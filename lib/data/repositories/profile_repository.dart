import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart';
import '../services/api_client.dart';

/// Everything the student can change about their own record.
///
/// Split out from [AuthRepository], which owns the session: this is the write
/// side of the profile, and it exists so the profile screen, the settings screen
/// and the dashboard's exam countdown all go through one place that knows which
/// fields `validProfileUpdate()` in firestore.rules will accept.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// The unsigned Cloudinary upload the website's ProfileView posts to. Kept
  /// identical so a photo set on either side shows on both.
  static const _cloudinaryCloud = 'dbprcgtog';
  static const _cloudinaryPreset = 'NLTC ONLINE';

  /// Cloudinary rejects anything larger, and so does the web form.
  static const maxAvatarBytes = 5 * 1024 * 1024;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  /// Writes [patch] onto the profile.
  ///
  /// Nulls are sent through as real nulls rather than dropped — clearing the exam
  /// date is how a student removes the countdown.
  Future<void> save(String uid, Map<String, dynamic> patch) =>
      _doc(uid).update({...patch, 'updatedAt': FieldValue.serverTimestamp()});

  // ─── Exam countdown ───────────────────────────────────────────────────────

  /// Points the dashboard countdown at [date], stored as the `yyyy-MM-dd` string
  /// the web writes so both read the same value.
  Future<void> setExamCountdown(String uid, String name, DateTime date) =>
      save(uid, {'examName': name, 'examDate': _dateKey(date)});

  Future<void> clearExamCountdown(String uid) =>
      save(uid, {'examName': null, 'examDate': null});

  // ─── Weekly goal ──────────────────────────────────────────────────────────

  /// Clamped to the same 1–21 range as the web's stepper.
  Future<void> setWeeklyGoal(String uid, int sessions) =>
      save(uid, {'weeklyGoal': sessions.clamp(1, 21)});

  // ─── Daily missions ───────────────────────────────────────────────────────

  /// Rolls the mission set over to a new day.
  Future<void> startDailyMission(
    String uid,
    String date,
    List<String> taskIds,
  ) =>
      save(uid, {
        'dailyMission': {'date': date, 'taskIds': taskIds, 'completed': []},
      });

  /// Ticks one task off.
  ///
  /// `arrayUnion` rather than a rewrite so two taps — or the app and the website
  /// at once — cannot drop each other's completion.
  Future<void> completeMission(String uid, String taskId) => _doc(uid).update({
        'dailyMission.completed': FieldValue.arrayUnion([taskId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ─── Avatar ───────────────────────────────────────────────────────────────

  /// Uploads [file] to Cloudinary and returns the secure URL.
  ///
  /// Written against `HttpClient` directly because this is the only multipart
  /// request in the app; pulling in a whole HTTP package for one form post isn't
  /// worth the dependency. Progress is reported as bytes are handed to the
  /// socket, which on a slow connection is close enough to the truth to drive a
  /// bar.
  Future<String> uploadAvatar(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > maxAvatarBytes) {
      throw const ApiException('Image must be under 5 MB.');
    }

    final boundary =
        '----nltc${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.postUrl(
        Uri.parse(
          'https://api.cloudinary.com/v1_1/$_cloudinaryCloud/image/upload',
        ),
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      final head = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="upload_preset"\r\n\r\n'
        '$_cloudinaryPreset\r\n'
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; '
        'filename="${_fileName(file)}"\r\n'
        'Content-Type: ${_mimeType(file)}\r\n\r\n',
      );
      final tail = utf8.encode('\r\n--$boundary--\r\n');

      request.contentLength = head.length + bytes.length + tail.length;
      request.add(head);

      // Chunked so the bar moves on a big photo instead of jumping 0 → 100.
      const chunk = 32 * 1024;
      for (var sent = 0; sent < bytes.length; sent += chunk) {
        final end = min(sent + chunk, bytes.length);
        request.add(bytes.sublist(sent, end));
        await request.flush();
        onProgress?.call(end / bytes.length);
      }

      request.add(tail);
      final response = await request.close().timeout(
            const Duration(seconds: 60),
          );
      final body = await response.transform(utf8.decoder).join();

      final decoded = jsonDecode(body);
      final url = decoded is Map ? decoded['secure_url'] : null;
      if (response.statusCode != 200 || url is! String) {
        final message = decoded is Map && decoded['error'] is Map
            ? decoded['error']['message']?.toString()
            : null;
        throw ApiException(
          message ?? 'Upload failed. Please try again.',
          statusCode: response.statusCode,
        );
      }
      return url;
    } on SocketException {
      throw const ApiException(
        'No internet connection — the photo was not uploaded.',
        isOffline: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _fileName(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? 'avatar.jpg'
        : file.uri.pathSegments.last;
    return name.isEmpty ? 'avatar.jpg' : name;
  }

  static String _mimeType(File file) =>
      switch (file.path.toLowerCase().split('.').last) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' || 'heif' => 'image/heic',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };

  /// `yyyy-MM-dd`, the shape the web's `<input type="date">` produces.
  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Parses an `examDate` back out of the profile for display.
  static DateTime? parseDateKey(String? key) =>
      key == null ? null : DateTime.tryParse(key);

  /// Today, in the format [startDailyMission] and [AppUser.dailyMission] use.
  static String todayKey([DateTime? now]) => _dateKey(now ?? DateTime.now());
}

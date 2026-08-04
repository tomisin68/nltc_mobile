import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/subject.dart';
import '../services/firestore_cache.dart';

/// The subject picklist, Firestore-backed with a hardcoded fallback.
///
/// Port of `fetchSubjectNames` in `src/utils/subjects.js`. Admins maintain the
/// list in the web admin panel's Subjects tab; the app only reads it. When the
/// collection is empty or unreachable the shipped defaults stand in, so a picker
/// is never blank.
class SubjectRepository {
  SubjectRepository({
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
  })  : _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  static String _cacheKey(SubjectCategory category) =>
      'subjects_${category.wireName}';

  /// Sorted subject names for [category].
  Future<List<String>> names(SubjectCategory category) => _cache.read<List<String>>(
        _cacheKey(category),
        CacheTtl.subjects,
        () => _fetch(category),
        decode: (json) => (json as List).map((e) => e as String).toList(),
      );

  /// The same list, decorated with icons and colours for the subject grids.
  Future<List<Subject>> decorated(SubjectCategory category) async =>
      Subjects.decorate(await names(category));

  Future<List<String>> _fetch(SubjectCategory category) async {
    try {
      final snap = await _db
          .collection('subjects')
          .where('category', isEqualTo: category.wireName)
          .get();
      final names = snap.docs
          .map((d) => d.data()['name'])
          .whereType<String>()
          .where((n) => n.trim().isNotEmpty)
          .toList();
      final list = names.isEmpty ? Subjects.defaultsFor(category) : names;
      return list.toList()..sort((a, b) => a.compareTo(b));
    } catch (_) {
      // Offline or rules rejected the read — the shipped list is still useful.
      return Subjects.defaultsFor(category).toList()
        ..sort((a, b) => a.compareTo(b));
    }
  }
}

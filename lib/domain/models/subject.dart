import 'package:flutter/material.dart';

/// Which syllabus a subject belongs to.
enum SubjectCategory {
  senior('senior'),
  junior('junior');

  const SubjectCategory(this.wireName);

  /// The value stored in Firestore `subjects/{id}.category`.
  final String wireName;
}

/// A subject as the pickers render it: a name, plus the icon and colour that
/// make a grid of them scannable.
@immutable
class Subject {
  const Subject({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
  });

  /// Stable slug. Subjects the app shipped with keep the exact key the web uses,
  /// because it is what `/cbt?subject=` and the question bank match on.
  final String key;

  final String name;
  final IconData icon;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is Subject && other.key == key && other.name == name;

  @override
  int get hashCode => Object.hash(key, name);
}

/// The subject picklist, and the icon/colour decoration for it.
///
/// Port of `src/utils/subjects.js` plus the `SUBJECT_DECOR` maps duplicated
/// across `CBTPracticeView`, `BECEPracticeView` and `StudyNotesView` on the web.
/// Admins can add subjects at runtime, so anything not listed here falls back to
/// a neutral book icon rather than being dropped.
abstract final class Subjects {
  /// The senior set the app shipped with. Doubles as the instant fallback so a
  /// picker never renders empty while the first Firestore read is in flight.
  static const seniorDefaults = <String>[
    'Mathematics',
    'English Language',
    'Biology',
    'Physics',
    'Chemistry',
    'Economics',
    'Commerce',
    'Accounting',
    'Literature in English',
    'Further Mathematics',
    'Christian Religious Knowledge',
    'Government',
    'Islamic Religious Knowledge',
    'Yoruba',
    'Civic Education',
    'Geography',
    'General Paper',
  ];

  static const juniorDefaults = <String>[
    'Mathematics',
    'English Language',
    'Basic Science',
    'Basic Technology',
    'Social Studies',
    'Business Studies',
    'Agricultural Science',
    'Civic Education',
    'Home Economics',
    'Physical & Health Education',
    'Cultural & Creative Arts',
    'Christian Religious Studies',
    'Islamic Religious Studies',
    'Yoruba',
  ];

  static List<String> defaultsFor(SubjectCategory category) =>
      category == SubjectCategory.senior ? seniorDefaults : juniorDefaults;

  /// `slugifySubject` — lowercase, non-alphanumerics collapsed to underscores.
  static String slugify(String name) => name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static const _fallbackIcon = Icons.menu_book_rounded;
  static const _fallbackColor = Color(0xFF64748B);

  /// Keyed by subject *name*, since that is what Firestore stores and what the
  /// question bank matches on. The key beside it is the slug the web already
  /// uses in URLs — `english` rather than `english_language`, for instance, so
  /// existing links keep working.
  static const _decor = <String, ({String key, IconData icon, Color color})>{
    // Senior
    'Mathematics': (
      key: 'mathematics',
      icon: Icons.calculate_rounded,
      color: Color(0xFF2E90FA),
    ),
    'English Language': (
      key: 'english',
      icon: Icons.book_rounded,
      color: Color(0xFF7A5AF8),
    ),
    'Biology': (
      key: 'biology',
      icon: Icons.eco_rounded,
      color: Color(0xFF16B364),
    ),
    'Physics': (
      key: 'physics',
      icon: Icons.blur_on_rounded,
      color: Color(0xFFF04438),
    ),
    'Chemistry': (
      key: 'chemistry',
      icon: Icons.science_rounded,
      color: Color(0xFF12B76A),
    ),
    'Economics': (
      key: 'economics',
      icon: Icons.bar_chart_rounded,
      color: Color(0xFFF79009),
    ),
    'Commerce': (
      key: 'commerce',
      icon: Icons.business_center_rounded,
      color: Color(0xFFE8A000),
    ),
    'Accounting': (
      key: 'accounting',
      icon: Icons.savings_rounded,
      color: Color(0xFF2D9D78),
    ),
    'Literature in English': (
      key: 'literature',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFF9E77ED),
    ),
    'Further Mathematics': (
      key: 'further_mathematics',
      icon: Icons.functions_rounded,
      color: Color(0xFF155EEF),
    ),
    'Christian Religious Knowledge': (
      key: 'crk',
      icon: Icons.church_rounded,
      color: Color(0xFFE77729),
    ),
    'Government': (
      key: 'government',
      icon: Icons.balance_rounded,
      color: Color(0xFF0BA5EC),
    ),
    'Islamic Religious Knowledge': (
      key: 'irs',
      icon: Icons.mosque_rounded,
      color: Color(0xFF059669),
    ),
    'Yoruba': (
      key: 'yoruba',
      icon: Icons.translate_rounded,
      color: Color(0xFFDC2626),
    ),
    'Civic Education': (
      key: 'civic_education',
      icon: Icons.flag_rounded,
      color: Color(0xFF0BA5EC),
    ),
    'Geography': (
      key: 'geography',
      icon: Icons.public_rounded,
      color: Color(0xFF0284C7),
    ),
    'General Paper': (
      key: 'generalpaper',
      icon: Icons.description_rounded,
      color: Color(0xFF6366F1),
    ),
    // Junior — the overlapping names above are reused as-is; these are the ones
    // that only exist on the junior syllabus.
    'Basic Science': (
      key: 'basic_science',
      icon: Icons.science_rounded,
      color: Color(0xFF12B76A),
    ),
    'Basic Technology': (
      key: 'basic_technology',
      icon: Icons.build_rounded,
      color: Color(0xFF0E9384),
    ),
    'Social Studies': (
      key: 'social_studies',
      icon: Icons.public_rounded,
      color: Color(0xFFF79009),
    ),
    'Business Studies': (
      key: 'business_studies',
      icon: Icons.business_center_rounded,
      color: Color(0xFFE8A000),
    ),
    'Agricultural Science': (
      key: 'agricultural_science',
      icon: Icons.grass_rounded,
      color: Color(0xFF16B364),
    ),
    'Home Economics': (
      key: 'home_economics',
      icon: Icons.home_rounded,
      color: Color(0xFF9E77ED),
    ),
    'Physical & Health Education': (
      key: 'physical_health',
      icon: Icons.directions_run_rounded,
      color: Color(0xFFF04438),
    ),
    'Cultural & Creative Arts': (
      key: 'cultural_creative',
      icon: Icons.palette_rounded,
      color: Color(0xFFE77729),
    ),
    'Christian Religious Studies': (
      key: 'christian_rs',
      icon: Icons.church_rounded,
      color: Color(0xFFD97706),
    ),
    'Islamic Religious Studies': (
      key: 'islamic_rs',
      icon: Icons.mosque_rounded,
      color: Color(0xFF059669),
    ),
  };

  /// `decorateSubjects` — pairs each name with its icon and colour.
  static List<Subject> decorate(Iterable<String> names) =>
      names.map(one).toList(growable: false);

  /// One subject's decoration — for the screens that render a subject at a time
  /// rather than a grid of them, such as the weekly timetable.
  static Subject one(String name) {
    final decor = _decor[name];
    return Subject(
      key: decor?.key ?? slugify(name),
      name: name,
      icon: decor?.icon ?? _fallbackIcon,
      color: decor?.color ?? _fallbackColor,
    );
  }
}

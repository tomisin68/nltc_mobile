import 'passage_slot.dart';

/// How a sitting behaves once it starts.
enum ExamMode {
  /// Timed, no feedback until submission — the real thing.
  exam,

  /// Untimed, and the answer is revealed as soon as it's chosen.
  practice,
}

/// One subject's block of questions inside a paper.
///
/// A JAMB paper is four of these — English then three chosen subjects — laid end
/// to end in one flat question list. Keeping the list flat rather than nesting it
/// means the runner, the palette, the answer sheet and the attempt record all
/// stay exactly as they are for a single-subject sitting, which is a paper of
/// one section.
class ExamSection {
  const ExamSection({
    required this.key,
    required this.name,
    required this.start,
    required this.length,
  });

  /// The subject's slug — `further_mathematics`. What the learning engine and the
  /// subject decoration are keyed by.
  final String key;

  /// The display name — `Further Mathematics`.
  final String name;

  /// Index of this section's first question in the paper's flat list.
  final int start;
  final int length;

  /// Exclusive.
  int get end => start + length;

  bool contains(int index) => index >= start && index < end;

  /// The question number a student sees, which restarts at 1 in every subject
  /// exactly as it does in the real hall.
  int numberAt(int index) => index - start + 1;
}

/// Which exam the sitting imitates.
///
/// The keys are the `exam` values the backend records and the web sends, so a
/// sitting taken in the app lands in the same bucket in exam history.
///
/// `custom` is the paper a student builds themselves — any number of subjects,
/// their own question counts, their own clock. It carries no default duration
/// because choosing one is the whole point of it.
enum CbtExam {
  jamb('jamb', 'JAMB', 'English + 3 subjects · 2 hrs'),
  study('study', 'Study Mode', 'Instant answers & explanations'),
  waec('waec', 'WAEC', '1 subject · 45 min'),
  postUtme('postutme', 'Post UTME', '1 subject · 30 min'),
  topic('topic', 'Topic', 'Practice by topic'),
  bece('bece', 'BECE', 'Junior past questions'),
  practice('practice', 'Practice', 'Your own settings'),
  custom('custom', 'Custom CBT', 'Your subjects · your clock');

  const CbtExam(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  /// English carries 60 questions in UTME; every other subject carries 40.
  static const jambEnglishCount = 60;
  static const jambSubjectCount = 40;

  /// Where the two passage-based sets sit in a UTME English paper: the
  /// comprehension passage is questions 1-5 and the cloze passage is 16-25,
  /// each drawn whole from one passage rather than question by question. The
  /// other 45 are drawn independently, as every other subject's are.
  static const jambEnglishPassages = [
    PassageSlot(
      topic: 'Reading Comprehension',
      keyword: 'comprehension',
      start: 0,
      length: 5,
    ),
    PassageSlot(
      topic: 'Cloze Test',
      keyword: 'cloze',
      start: 15,
      length: 10,
    ),
  ];

  /// Fixed for JAMB, a sensible default elsewhere, and null where the student
  /// chooses. Mirrors `DEFAULT_TIMERS` and the JAMB branch on the web.
  Duration? get defaultDuration => switch (this) {
        CbtExam.jamb => const Duration(hours: 2),
        CbtExam.waec => const Duration(minutes: 45),
        CbtExam.postUtme => const Duration(minutes: 30),
        _ => null,
      };
}

/// Everything chosen on the setup sheet before an exam begins.
///
/// Immutable and passed down whole, so the runner never has to guess whether
/// it's timing a sitting or coaching one.
class ExamConfig {
  const ExamConfig({
    required this.subject,
    required this.exam,
    required this.questionCount,
    required this.mode,
    this.topic,
    this.duration,
    this.sections = const [],
    this.scoresOutOf400 = false,
    this.subjectKey,
  });

  final String subject;

  /// The board this sitting imitates — 'JAMB / UTME', 'WAEC', 'NECO'. Sent to
  /// the backend with the attempt.
  final String exam;

  final String? topic;
  final int questionCount;
  final ExamMode mode;

  /// Null in practice mode, where nothing is being timed.
  final Duration? duration;

  /// The subjects this paper is made of, in order.
  ///
  /// Empty for a single-subject sitting, which is the common case — [sectionList]
  /// synthesises the one section such a paper implies, so callers never have to
  /// branch on whether a paper is multi-subject.
  final List<ExamSection> sections;

  /// Whether the result is reported as a JAMB aggregate out of 400 rather than a
  /// percentage. Only true for a full four-subject UTME paper.
  final bool scoresOutOf400;

  /// The subject's slug, when the caller knows it. Used to look up the student's
  /// ability for this subject and to tag answers for the learning engine.
  final String? subjectKey;

  bool get isMultiSubject => sections.length > 1;

  /// [sections], or the single implied section covering the whole paper.
  List<ExamSection> get sectionList => sections.isNotEmpty
      ? sections
      : [
          ExamSection(
            key: subjectKey ?? subject,
            name: subject,
            start: 0,
            length: questionCount,
          ),
        ];

  bool get isTimed => mode == ExamMode.exam && duration != null;

  /// Whether the correct answer is shown the moment one is picked.
  bool get revealsAnswers => mode == ExamMode.practice;

  /// The default clock for a sitting: a minute a question, which is the pace
  /// JAMB actually sets (180 questions in 180 minutes).
  static Duration defaultDuration(int questionCount) =>
      Duration(minutes: questionCount);

  static const examBoards = ['JAMB / UTME', 'WAEC', 'NECO'];

  ExamConfig copyWith({
    String? subject,
    String? exam,
    Object? topic = _unset,
    int? questionCount,
    ExamMode? mode,
    Object? duration = _unset,
    List<ExamSection>? sections,
    bool? scoresOutOf400,
    Object? subjectKey = _unset,
  }) =>
      ExamConfig(
        subject: subject ?? this.subject,
        exam: exam ?? this.exam,
        topic: topic == _unset ? this.topic : topic as String?,
        questionCount: questionCount ?? this.questionCount,
        mode: mode ?? this.mode,
        duration: duration == _unset ? this.duration : duration as Duration?,
        sections: sections ?? this.sections,
        scoresOutOf400: scoresOutOf400 ?? this.scoresOutOf400,
        subjectKey:
            subjectKey == _unset ? this.subjectKey : subjectKey as String?,
      );

  /// Sentinel so `copyWith` can tell "leave it alone" apart from "set to null".
  static const _unset = Object();
}

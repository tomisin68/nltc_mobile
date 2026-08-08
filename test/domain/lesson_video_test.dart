import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/repositories/video_repository.dart';
import 'package:nltc/domain/models/lesson_video.dart';

LessonVideo _video(Map<String, dynamic> fields) =>
    LessonVideo.fromJson('v1', {'title': 'A lesson', ...fields});

void main() {
  group('class filing', () {
    test('reads the classes a lesson was filed under', () {
      final video = _video({
        'classLevels': ['sss1', 'sss3'],
      });

      expect(video.classLevels, {ClassLevel.sss1, ClassLevel.sss3});
      expect(video.matchesClass(ClassLevel.sss1), isTrue);
      expect(video.matchesClass(ClassLevel.sss2), isFalse);
    });

    test('a legacy upload with no classLevels sits on every shelf', () {
      final video = _video({});

      expect(video.classLevels, isEmpty);
      for (final level in ClassLevel.values) {
        expect(video.matchesClass(level), isTrue);
      }
    });

    test('junk keys are dropped, which puts the lesson back on every shelf', () {
      final video = _video({
        'classLevels': ['jss1', 42, ''],
      });

      expect(video.classLevels, isEmpty);
      expect(video.matchesClass(ClassLevel.sss2), isTrue);
    });

    test('wire names are matched case-insensitively', () {
      expect(
        _video({
          'classLevels': ['SSS2'],
        }).classLevels,
        {ClassLevel.sss2},
      );
    });

    test('no shelf chosen means the whole library', () {
      expect(
        _video({
          'classLevels': ['sss1'],
        }).matchesClass(null),
        isTrue,
      );
    });
  });

  group('topic tags', () {
    test('an untagged lesson is filed under General, not lost', () {
      expect(_video({}).topicOrDefault, kUntaggedTopic);
      expect(_video({'topic': '   '}).topicOrDefault, kUntaggedTopic);
    });

    test('a tagged lesson keeps its trimmed tag', () {
      expect(
        _video({'topic': '  Quadratic Equations '}).topicOrDefault,
        'Quadratic Equations',
      );
    });
  });

  group('fromJson', () {
    test('reads the expert and falls back to the legacy videoUrl field', () {
      final video = _video({
        'teacher': 'Mr Adeyemi',
        'videoUrl': 'https://youtu.be/dQw4w9WgXcQ',
      });

      expect(video.teacher, 'Mr Adeyemi');
      expect(video.youTubeId, 'dQw4w9WgXcQ');
    });

    test('the canonical url field wins over the legacy one', () {
      final video = _video({
        'url': 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
        'videoUrl': 'https://youtu.be/bbbbbbbbbbb',
      });

      expect(video.youTubeId, 'aaaaaaaaaaa');
    });
  });

  group('search', () {
    final video = _video({
      'title': 'JAMB Maths crash course',
      'subject': 'Mathematics',
      'topic': 'Quadratic Equations',
      'teacher': 'Mr Adeyemi',
      'description': 'Completing the square',
    });

    test('matches on topic, which is what the box is for', () {
      expect(video.matchesSearch('quadratic'), isTrue);
    });

    test('also matches title, subject, expert and description', () {
      for (final needle in ['crash', 'mathematics', 'adeyemi', 'square']) {
        expect(video.matchesSearch(needle), isTrue, reason: needle);
      }
    });

    test('misses what is not there; an empty query matches everything', () {
      expect(video.matchesSearch('photosynthesis'), isFalse);
      expect(video.matchesSearch('   '), isTrue);
    });

    test('survives a lesson with nothing but a title', () {
      expect(_video({}).matchesSearch('lesson'), isTrue);
      expect(_video({}).matchesSearch('photosynthesis'), isFalse);
    });
  });

  group('VideoRepository.buildShelves', () {
    const bank = ['Algebra', 'Quadratic Equations', 'Trigonometry'];

    test('lists every bank topic, even the ones with no lessons yet', () {
      final shelves = VideoRepository.buildShelves(bank, const []);

      expect(
        shelves.map((s) => s.topic),
        ['Algebra', 'Quadratic Equations', 'Trigonometry'],
      );
      expect(shelves.every((s) => !s.hasVideos), isTrue);
    });

    test('groups several experts onto the one topic', () {
      final shelves = VideoRepository.buildShelves(bank, [
        _video({'topic': 'Algebra', 'teacher': 'Mr A'}),
        _video({'topic': 'algebra', 'teacher': 'Ms B'}),
      ]);
      final algebra = shelves.firstWhere((s) => s.topic == 'Algebra');

      expect(algebra.videos, hasLength(2));
      expect(algebra.expertCount, 2);
    });

    test('counts one expert once, however many lessons they filmed', () {
      final shelves = VideoRepository.buildShelves(bank, [
        _video({'topic': 'Algebra', 'teacher': 'Mr A'}),
        _video({'topic': 'Algebra', 'teacher': 'Mr A'}),
      ]);

      expect(shelves.firstWhere((s) => s.topic == 'Algebra').expertCount, 1);
    });

    test('keeps a lesson whose topic left the bank, sorted after it', () {
      final shelves = VideoRepository.buildShelves(bank, [
        _video({'topic': 'Surds'}),
      ]);

      expect(
        shelves.map((s) => s.topic),
        ['Algebra', 'Quadratic Equations', 'Trigonometry', 'Surds'],
      );
      expect(shelves.last.videos, hasLength(1));
    });

    test('shelves untagged lessons under General', () {
      final shelves = VideoRepository.buildShelves(bank, [_video({})]);

      expect(
        shelves.firstWhere((s) => s.topic == kUntaggedTopic).videos,
        hasLength(1),
      );
    });

    test('works with no bank at all — the lessons shelve themselves', () {
      final shelves = VideoRepository.buildShelves(const [], [
        _video({'topic': 'Surds'}),
      ]);

      expect(shelves, hasLength(1));
      expect(shelves.single.topic, 'Surds');
    });
  });
}

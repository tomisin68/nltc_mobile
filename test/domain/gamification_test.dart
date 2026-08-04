import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/models/gamification.dart';

/// The level ladder is duplicated in three places — this file, the web's
/// `AuthContext.jsx`, and the backend's `gamificationService.js`. These tests
/// pin the values the other two use, so a change on either side fails here
/// rather than quietly showing a student a level the backend never awarded.
void main() {
  group('Levels.forXp', () {
    test('starts at level 1 with no XP at all', () {
      expect(Levels.forXp(0), 1);
      expect(Levels.nameForXp(0), 'Starter');
    });

    test('lands on each threshold exactly, not one past it', () {
      expect(Levels.forXp(500), 2);
      expect(Levels.forXp(1500), 3);
      expect(Levels.forXp(3500), 4);
      expect(Levels.forXp(7000), 5);
      expect(Levels.forXp(12000), 6);
      expect(Levels.forXp(20000), 7);
    });

    test('one XP short of a threshold is still the level below', () {
      expect(Levels.forXp(499), 1);
      expect(Levels.forXp(1499), 2);
      expect(Levels.forXp(19999), 6);
    });

    test('names match the web list in order', () {
      expect(Levels.names, [
        'Starter',
        'Scholar',
        'Explorer',
        'Achiever',
        'Champion',
        'Elite',
        'Legend',
      ]);
    });

    test('past the top threshold the student stays Legend', () {
      expect(Levels.forXp(1000000), 7);
      expect(Levels.nameForXp(1000000), 'Legend');
    });
  });

  group('Levels.progressInLevel', () {
    test('is zero on the threshold that opens a level', () {
      expect(Levels.progressInLevel(0), 0);
      expect(Levels.progressInLevel(500), 0);
      expect(Levels.progressInLevel(1500), 0);
    });

    test('is halfway between two thresholds', () {
      // Level 2 runs 500 → 1500, so 1000 is the midpoint.
      expect(Levels.progressInLevel(1000), closeTo(0.5, 1e-9));
      // Level 3 runs 1500 → 3500.
      expect(Levels.progressInLevel(2500), closeTo(0.5, 1e-9));
    });

    test('never leaves the 0..1 range the XP bar can draw', () {
      for (final xp in [0, 1, 499, 500, 7000, 19999, 20000, 999999999]) {
        final progress = Levels.progressInLevel(xp);
        expect(progress, greaterThanOrEqualTo(0), reason: 'xp=$xp');
        expect(progress, lessThanOrEqualTo(1), reason: 'xp=$xp');
      }
    });

    test('the top level reports full rather than dividing by zero', () {
      expect(Levels.progressInLevel(20000), lessThanOrEqualTo(1));
      expect(Levels.progressInLevel(999999), 1);
    });
  });

  group('Levels.nextLevelXp', () {
    test('counts toward the threshold that ends the current level', () {
      expect(Levels.nextLevelXp(0), 500);
      expect(Levels.nextLevelXp(499), 500);
      expect(Levels.nextLevelXp(500), 1500);
      expect(Levels.nextLevelXp(12000), 20000);
    });

    test('holds at the last threshold once there is nothing left to climb', () {
      expect(Levels.nextLevelXp(20000), 20000);
      expect(Levels.nextLevelXp(50000), 20000);
    });
  });
}

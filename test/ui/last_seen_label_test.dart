import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/ui/core/format.dart';

/// The line under a name in a conversation. It gets vaguer the further back it
/// goes on purpose — the exact minute somebody was last online three weeks ago
/// is not something a study app should be telling anyone.
void main() {
  DateTime ago(Duration d) => DateTime.now().subtract(d);

  group('lastSeenLabel', () {
    test('says nothing it does not know', () {
      expect(lastSeenLabel(null), 'Offline');
    });

    test('rounds the first minute to "just now"', () {
      expect(lastSeenLabel(ago(const Duration(seconds: 20))), 'Last seen just now');
    });

    test('counts minutes for the first hour', () {
      expect(lastSeenLabel(ago(const Duration(minutes: 5))), 'Last seen 5m ago');
      expect(lastSeenLabel(ago(const Duration(minutes: 59))), 'Last seen 59m ago');
    });

    test('gives a clock time later the same day', () {
      final when = DateTime.now().subtract(const Duration(hours: 3));
      final label = lastSeenLabel(when);
      // Only meaningful when three hours ago was still today; on a very early
      // morning run it correctly rolls over to the yesterday form instead.
      final sameDay = when.day == DateTime.now().day;
      expect(label, startsWith(sameDay ? 'Last seen ' : 'Last seen yesterday'));
      expect(label, contains(':'));
    });

    test('names yesterday rather than giving a bare time', () {
      final when = DateTime.now()
          .subtract(const Duration(days: 1))
          .copyWith(hour: 12, minute: 30);
      expect(lastSeenLabel(when), startsWith('Last seen yesterday at '));
    });

    test('uses the weekday within the last week', () {
      final label = lastSeenLabel(ago(const Duration(days: 3)));
      expect(label, startsWith('Last seen '));
      expect(label, isNot(contains(':')));
    });

    test('falls back to a date once it is more than a week ago', () {
      expect(lastSeenLabel(ago(const Duration(days: 30))), startsWith('Last seen '));
      expect(lastSeenLabel(ago(const Duration(days: 30))), isNot(contains(':')));
    });
  });
}

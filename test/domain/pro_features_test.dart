import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/pro_features.dart';

void main() {
  group('ProFeature', () {
    test('covers exactly the three features a free account is held out of', () {
      expect(
        ProFeature.values.map((f) => f.label),
        containsAll(<String>['Messages', 'Live Classes', 'My Wrapped']),
      );
      expect(ProFeature.values, hasLength(3));
    });

    test('every feature can explain itself', () {
      for (final feature in ProFeature.values) {
        expect(feature.label, isNotEmpty, reason: feature.name);
        expect(feature.note, isNotEmpty, reason: feature.name);
        expect(feature.body, isNotEmpty, reason: feature.name);
        // Three bullets on the panel — the layout is built for three, and a
        // gate that lists one perk is not an offer.
        expect(feature.perks, hasLength(3), reason: feature.name);
      }
    });

    test('the label matches the sidebar link it gates', () {
      // A student taps "My Wrapped" and must be told about "My Wrapped" — a
      // gate that renames the thing it is guarding reads as a different
      // feature. These strings are the sidebar's, verbatim.
      expect(ProFeature.messages.label, 'Messages');
      expect(ProFeature.liveClasses.label, 'Live Classes');
      expect(ProFeature.wrapped.label, 'My Wrapped');
    });
  });
}

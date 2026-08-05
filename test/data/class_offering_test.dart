import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/repositories/billing_repository.dart';

/// UNIT — class/fee targeting.
///
/// Mirrors `src/tests/utils/classes.test.js` on the website: a student must only
/// ever be offered the fee that concerns them — their study mode crossed with
/// their level — and never one an admin has closed.
void main() {
  ClassOffering fee(
    String id,
    String name,
    int price, {
    String? audience,
    String? level,
    String type = 'general',
    bool active = true,
  }) =>
      ClassOffering(
        id: id,
        name: name,
        price: price,
        type: type,
        audience: audience,
        level: level,
        active: active,
      );

  final catalogue = [
    fee('on-s', 'Online Senior', 3000, audience: 'online', level: 'senior'),
    fee('on-j', 'Online Junior', 2500, audience: 'online', level: 'junior'),
    fee('mo-s', 'Morning Senior', 15000,
        audience: 'physical', level: 'senior', type: 'morning'),
    fee('ev-s', 'Evening Senior', 12000,
        audience: 'physical', level: 'senior', type: 'evening'),
    fee('mo-j', 'Morning Junior', 10000,
        audience: 'physical', level: 'junior', type: 'morning'),
    fee('off', 'Retired Class', 5000,
        audience: 'physical', level: 'senior', active: false),
  ];

  List<String> namesFor({required bool isPhysical, required bool isJunior}) =>
      filterClassesForStudent(
        catalogue,
        isPhysical: isPhysical,
        isJunior: isJunior,
      ).map((c) => c.name).toList();

  group('normalising legacy class docs', () {
    test('infers the online audience from type when audience is missing', () {
      expect(
        ClassOffering.fromMap('x', {'type': 'online'}).resolvedAudience,
        'online',
      );
    });

    test('treats every other legacy type as a centre fee', () {
      expect(
        ClassOffering.fromMap('x', {'type': 'morning'}).resolvedAudience,
        'physical',
      );
      expect(ClassOffering.fromMap('x', const {}).resolvedAudience, 'physical');
    });

    test('shows legacy docs to both levels rather than hiding them', () {
      expect(ClassOffering.fromMap('x', const {}).resolvedLevel, 'both');
      expect(
        ClassOffering.fromMap('x', {'level': 'nonsense'}).resolvedLevel,
        'both',
      );
    });

    test('is open unless an admin explicitly closed it', () {
      expect(ClassOffering.fromMap('x', const {}).active, isTrue);
      expect(ClassOffering.fromMap('x', {'active': true}).active, isTrue);
      expect(ClassOffering.fromMap('x', {'active': false}).active, isFalse);
    });
  });

  group('filterClassesForStudent', () {
    test('shows an online senior student only their online fee', () {
      expect(
        namesFor(isPhysical: false, isJunior: false),
        ['Online Senior'],
      );
    });

    test('shows an online junior student only their online fee', () {
      expect(namesFor(isPhysical: false, isJunior: true), ['Online Junior']);
    });

    test('shows a physical senior student only the senior centre fees', () {
      expect(
        namesFor(isPhysical: true, isJunior: false),
        ['Evening Senior', 'Morning Senior'],
      );
    });

    test('shows a physical junior student only the junior centre fee', () {
      expect(namesFor(isPhysical: true, isJunior: true), ['Morning Junior']);
    });

    test('sorts cheapest first', () {
      final visible = filterClassesForStudent(
        catalogue,
        isPhysical: true,
        isJunior: false,
      );
      expect(visible.first.price, lessThan(visible[1].price));
    });

    test('hides deactivated fees', () {
      expect(
        namesFor(isPhysical: true, isJunior: false),
        isNot(contains('Retired Class')),
      );
    });

    test('shows an audience:both / level:both fee to everyone', () {
      final all = [
        ...catalogue,
        fee('any', 'Everyone', 1, audience: 'both', level: 'both'),
      ];
      for (final student in [
        (physical: false, junior: false),
        (physical: true, junior: true),
      ]) {
        expect(
          filterClassesForStudent(
            all,
            isPhysical: student.physical,
            isJunior: student.junior,
          ).map((c) => c.name),
          contains('Everyone'),
        );
      }
    });

    test('returns an empty list rather than throwing on no input', () {
      expect(
        filterClassesForStudent(const [], isPhysical: true, isJunior: false),
        isEmpty,
      );
    });
  });

  group('the fees this centre actually has published', () {
    // The three live docs, which predate `audience` and `level` entirely.
    final live = [
      ClassOffering.fromMap('i0sJ', {
        'name': 'Morning JAMB/POST-UTME ',
        'price': 12000,
        'type': 'morning',
        'active': false,
      }),
      ClassOffering.fromMap('kxee', {
        'name': 'Evening Class (Senior Secondary)',
        'price': 10000,
        'type': 'evening',
        'active': true,
      }),
      ClassOffering.fromMap('nQEe', {
        'name': 'Evening Class (Junior Secondary)',
        'price': 8000,
        'type': 'evening',
        'active': true,
      }),
    ];

    test('never offers the deactivated morning class', () {
      for (final physical in [true, false]) {
        for (final junior in [true, false]) {
          expect(
            filterClassesForStudent(
              live,
              isPhysical: physical,
              isJunior: junior,
            ).map((c) => c.id),
            isNot(contains('i0sJ')),
            reason: 'physical=$physical junior=$junior',
          );
        }
      }
    });

    test('keeps centre fees away from online students', () {
      expect(
        filterClassesForStudent(live, isPhysical: false, isJunior: false),
        isEmpty,
      );
    });
  });
}

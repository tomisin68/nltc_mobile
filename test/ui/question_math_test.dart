import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/ui/core/widgets/question_body.dart';
import 'package:nltc/ui/core/widgets/question_math.dart';

/// WIDGET — maths notation in a question.
///
/// Mirrors `src/tests/unit/questionMath.test.js` on the website. The fixtures
/// are the markup byte-for-byte as the question bank stores it, so the two
/// clients are demonstrably reading the same thing.
///
/// The failure this guards against is quiet. `HtmlWidget` renders `<table>` as
/// a block and understands neither `display:inline-table` nor `border-radius`,
/// so before [QuestionMath] a fraction dropped out of its sentence onto a line
/// of its own and a matrix lost the brackets that make it a matrix. Nothing
/// threw — the question just stopped meaning what the paper meant. That is why
/// these tests measure geometry rather than assert that a widget was built.
void main() {
  const fraction =
      '<table style="display:inline-table;vertical-align:middle;text-align:center;'
      'border-collapse:collapse;margin:0 2px;"><tr><td style="border-bottom:1.5px '
      'solid #000;padding:1px 6px;">3x + 5</td></tr><tr><td style="padding:1px 6px;">'
      '(x + 1)(x + 2)</td></tr></table>';

  const matrix =
      '<table style="display:inline-table;vertical-align:middle;border-left:2px '
      'solid #000;border-right:2px solid #000;border-radius:8px/50%;padding:2px 5px;'
      'border-collapse:separate;"><tr><td style="padding:1px 7px;text-align:center;">1'
      '</td><td style="padding:1px 7px;text-align:center;">2</td></tr><tr>'
      '<td style="padding:1px 7px;text-align:center;">3</td>'
      '<td style="padding:1px 7px;text-align:center;">4</td></tr></table>';

  const radical =
      '&radic;<span style="text-decoration:overline;padding:0 2px;">12</span>';

  const nested =
      '&radic;<span style="text-decoration:overline;padding:0 2px;">$fraction</span>';

  const body = Key('question-body');

  Future<Size> show(WidgetTester tester, String html) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichQuestionText(
              key: body,
              html: html,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byKey(body));
  }

  Finder txt(String s) => find.text(s, findRichText: true);

  group('a stacked fraction', () {
    testWidgets('shows both rows, one above the other and centred', (tester) async {
      await show(tester, 'Resolve $fraction into partial fractions.');

      expect(txt('3x + 5'), findsOneWidget);
      expect(txt('(x + 1)(x + 2)'), findsOneWidget);

      final numerator = tester.getCenter(txt('3x + 5'));
      final denominator = tester.getCenter(txt('(x + 1)(x + 2)'));
      expect(numerator.dy, lessThan(denominator.dy));
      expect((numerator.dx - denominator.dx).abs(), lessThan(1.0));
    });

    testWidgets('draws the bar across the wider row, not across the screen', (tester) async {
      final paragraph = await show(tester, fraction);

      final bar = tester.getSize(find.byKey(fractionBarKey));
      final wider = tester.getSize(txt('(x + 1)(x + 2)')).width;

      // A rule, not a band — the measurement includes the margin either side.
      expect(bar.height, lessThan(5));
      expect(bar.width, greaterThanOrEqualTo(wider));
      // The bug this replaces: a bar with no intrinsic width taking the whole
      // line, which dragged the fraction across the page with it.
      expect(bar.width, lessThan(wider + 40));
      expect(paragraph.width, lessThan(400));
    });

    testWidgets('stays on the line it was written into', (tester) async {
      final alone = await show(tester, fraction);
      final inSentence = await show(tester, 'Resolve $fraction into partial fractions.');
      final prose = await show(tester, 'Resolve this into partial fractions.');

      // One line, whose height is the fraction's. Rendered as a block the
      // paragraph would be the fraction plus a line of text above and below.
      expect(inSentence.height, lessThan(alone.height + prose.height));
      expect((inSentence.height - alone.height).abs(), lessThan(6));
    });
  });

  group('a matrix', () {
    testWidgets('lays its entries out as a grid, not as a list', (tester) async {
      await show(tester, 'Evaluate $matrix here.');

      for (final entry in ['1', '2', '3', '4']) {
        expect(txt(entry), findsOneWidget);
      }

      final one = tester.getCenter(txt('1'));
      final two = tester.getCenter(txt('2'));
      final three = tester.getCenter(txt('3'));

      // 1 and 2 share a row; 3 sits on the next row, under 1.
      expect((one.dy - two.dy).abs(), lessThan(1.0));
      expect(two.dx, greaterThan(one.dx));
      expect(three.dy, greaterThan(one.dy));
      expect((three.dx - one.dx).abs(), lessThan(1.0));
    });

    testWidgets('draws a rounded bracket down each side', (tester) async {
      await show(tester, matrix);

      final container = tester.widget<Container>(find.byKey(matrixKey));
      final decoration = container.decoration! as BoxDecoration;
      final border = decoration.border! as Border;

      expect(border.left.width, greaterThan(0));
      expect(border.right.width, greaterThan(0));
      expect(border.top.style, BorderStyle.none);
      expect(border.bottom.style, BorderStyle.none);
      // Rounded, which is what makes two sides read as brackets rather than as
      // a box missing its top and bottom.
      expect(decoration.borderRadius, isNotNull);
      // Both sides the same colour, which is what lets Flutter paint a radius
      // on a border that is not uniform.
      expect(border.left.color, border.right.color);
    });

    testWidgets('stays on the line it was written into', (tester) async {
      final alone = await show(tester, matrix);
      final inSentence = await show(tester, 'Evaluate $matrix here.');
      expect((inSentence.height - alone.height).abs(), lessThan(6));
    });
  });

  group('a surd', () {
    testWidgets('shows the radical sign and its radicand', (tester) async {
      await show(tester, 'Simplify $radical now.');
      expect(find.textContaining('√', findRichText: true), findsOneWidget);
      expect(find.textContaining('12', findRichText: true), findsOneWidget);
    });

    testWidgets('stretches the overline across a nested fraction', (tester) async {
      await show(tester, nested);

      // Both halves of the fraction survive inside the radicand...
      expect(txt('3x + 5'), findsOneWidget);
      expect(txt('(x + 1)(x + 2)'), findsOneWidget);

      // ...and a rule is drawn over the whole of it, which a text decoration
      // could never have reached.
      final rule = tester.widget<Container>(find.byKey(overlineKey));
      final border = (rule.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, greaterThan(0));

      final overline = tester.getSize(find.byKey(overlineKey));
      final bar = tester.getSize(find.byKey(fractionBarKey));
      expect(overline.width, greaterThanOrEqualTo(bar.width));
    });
  });

  group('nesting', () {
    testWidgets('draws a fraction inside a matrix cell', (tester) async {
      await show(tester, matrix.replaceFirst('>1<', '>$fraction<'));

      expect(txt('3x + 5'), findsOneWidget);
      expect(txt('(x + 1)(x + 2)'), findsOneWidget);
      for (final entry in ['2', '3', '4']) {
        expect(txt(entry), findsOneWidget);
      }

      // The fraction is inside the brackets, not beside them.
      final brackets = tester.getRect(find.byKey(matrixKey));
      final bar = tester.getRect(find.byKey(fractionBarKey));
      expect(brackets.left, lessThan(bar.left));
      expect(brackets.right, greaterThan(bar.right));
    });
  });

  group('everything else is left alone', () {
    testWidgets('an ordinary table is still a table, not notation', (tester) async {
      await show(
        tester,
        '<table><tr><td>Year</td><td>Yield</td></tr>'
        '<tr><td>2023</td><td>40</td></tr></table>',
      );
      expect(txt('Year'), findsOneWidget);
      expect(txt('2023'), findsOneWidget);
      expect(find.byKey(fractionBarKey), findsNothing);
      expect(find.byKey(matrixKey), findsNothing);
    });

    testWidgets('indices and chemical formulae still render', (tester) async {
      await show(tester, 'H<sub>2</sub>SO<sub>4</sub> when x<sup>2</sup> = 9');
      expect(find.textContaining('H', findRichText: true), findsOneWidget);
      expect(find.byKey(fractionBarKey), findsNothing);
    });

    testWidgets('inequality entities show as signs, not as escaped text', (tester) async {
      await show(tester, 'For which x is 2x &lt; 8 and x &le; 3?');
      expect(find.textContaining('<', findRichText: true), findsOneWidget);
      expect(find.textContaining('≤', findRichText: true), findsOneWidget);
      expect(find.textContaining('&lt;', findRichText: true), findsNothing);
    });

    testWidgets('plain prose takes no notation path at all', (tester) async {
      await show(tester, 'What is 2 + 2?');
      expect(QuestionMath.hasNotation('What is 2 + 2?'), isFalse);
      expect(QuestionMath.hasNotation(fraction), isTrue);
      expect(QuestionMath.hasNotation(matrix), isTrue);
      expect(QuestionMath.hasNotation(radical), isTrue);
    });
  });

  /* ── Figures ─────────────────────────────────────────────────────────────
     The bug these guard against was total and silent: `<svg>` was not on the
     website's sanitiser allowlist, so every diagram in the bank was deleted on
     import and again on render, and a circle-theorem question reached the exam
     hall as prose about a figure that was not there. On this side `HtmlWidget`
     draws no vectors at all, so even a diagram that survived would have arrived
     as a scatter of its own axis labels. */
  group('a figure', () {
    const circle =
        '<svg xmlns="http://www.w3.org/2000/svg" width="220" height="160" '
        'viewBox="0 0 220 160">'
        '<circle cx="110" cy="80" r="70" fill="none" stroke="#000" stroke-width="2"></circle>'
        '<line x1="40" y1="80" x2="180" y2="80" stroke="#000" stroke-width="2"></line>'
        '<text x="106" y="76" font-size="11">O</text></svg>';

    testWidgets('is drawn, at the size it was authored', (tester) async {
      await show(tester, 'In the diagram, O is the centre. Find angle x. $circle');

      final figure = find.byKey(figureKey);
      expect(figure, findsOneWidget);

      // Geometry, not construction: a figure laid out to nothing is still a
      // widget that builds without complaint, and is exactly what a student
      // would report as "the diagram is missing".
      final size = tester.getSize(figure);
      expect(size.width, greaterThan(100));
      expect(size.height, greaterThan(80));
    });

    testWidgets('keeps a light surface under it on the dark exam screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichQuestionText(
                html: circle,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `stroke="#000"` on a dark card is an invisible drawing. The figure
      // carries the white page it was drawn for.
      final box = tester.widget<Container>(find.byKey(figureKey));
      expect((box.decoration as BoxDecoration).color, Colors.white);
    });

    testWidgets('a figure wider than the phone is scaled down, not cropped', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await show(
        tester,
        '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="450" '
        'viewBox="0 0 900 450"><rect x="0" y="0" width="900" height="450" '
        'fill="none" stroke="#000"></rect></svg>',
      );

      final size = tester.getSize(find.byKey(figureKey));
      expect(size.width, lessThanOrEqualTo(360));
      // Scaled by its own ratio rather than squashed: 900×450 is 2:1, and the
      // 6px of padding on each side is the surface, not the drawing.
      expect(size.height - 12, closeTo((size.width - 12) / 2, 1));
    });

    testWidgets('its labels are drawn into it, not spilled into the sentence', (tester) async {
      await show(tester, 'Find angle x. $circle');

      expect(find.textContaining('Find angle x', findRichText: true), findsOneWidget);
      // "O" is a label inside the drawing. Before this, `HtmlWidget` walked
      // into the `<svg>` and set it as a word in the question.
      expect(find.textContaining('O', findRichText: true), findsNothing);
    });
  });
}

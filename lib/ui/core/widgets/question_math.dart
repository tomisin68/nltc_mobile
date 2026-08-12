import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

/// Mathematical notation, and figures, inside a question.
///
/// A maths paper is not plain text and not MathML. The bank draws its notation
/// with inline CSS, because that is what renders identically in a browser, in
/// the admin preview and in an exported file an author can proof by eye:
///
///   * a **fraction** is a two-row inline table whose bar is the numerator
///     cell's `border-bottom`,
///   * a **matrix** is one table whose brackets are its `border-left` and
///     `border-right`, rounded with `border-radius`,
///   * a **surd** is `√` followed by a span with `text-decoration:overline`
///     stretched across the radicand.
///
/// `HtmlWidget` alone cannot draw those. It renders `<table>` as a *block*, so
/// a fraction would break the sentence it sits in and land on its own line, and
/// it understands neither `display:inline-table` nor `border-radius` — so a
/// matrix would lose its rounded brackets and a fraction its place in the line.
///
/// So the three constructs are recognised here and drawn as real Flutter
/// widgets, placed inline against the text via [InlineCustomWidget]. Everything
/// else is left to `HtmlWidget`, which handles `<sub>`, `<sup>` and the rest
/// perfectly well.
///
/// A **figure** is the fourth. A circle-theorem, bar-chart or bearing question
/// *is* its drawing — "find angle x" means nothing without the circle and the
/// labelled centre — and the bank writes those as inline SVG inside the
/// question text, because an SVG is text: it survives the line-based upload
/// format and needs no hosting. `HtmlWidget` renders markup, not vectors, so an
/// `<svg>` left to it contributes nothing but its stray `<text>` labels. It is
/// intercepted here and drawn with `flutter_svg`.
///
/// Borders are drawn in the current text colour rather than the `#000` the
/// markup asks for: the exam hall has a dark theme, and a black bar on a dark
/// navy card is an invisible bar. The web stylesheet overrides the same way.
class QuestionMath {
  const QuestionMath._();

  /// The renderer to hand to `HtmlWidget.customWidgetBuilder`.
  ///
  /// Returns `null` for anything that is not notation, which is how the rest of
  /// a question keeps its ordinary handling.
  static Widget? build(dom.Element element, {required TextStyle style}) {
    final kind = _kindOf(element);
    if (kind == null) return null;

    return InlineCustomWidget(
      alignment: PlaceholderAlignment.middle,
      child: switch (kind) {
        _MathKind.fraction => _Fraction(element: element, style: style),
        _MathKind.matrix => _Matrix(element: element, style: style),
        _MathKind.overline => _Overline(element: element, style: style),
        _MathKind.figure => _Figure(element: element),
      },
    );
  }

  /// True when [html] contains notation this renderer would take over.
  ///
  /// Used to decide whether a line needs the extra room two-row-tall notation
  /// takes up, so a plain prose question is not loosened for nothing.
  static bool hasNotation(String html) => _notation.hasMatch(html);
  static final _notation = RegExp(
    r'border-bottom|border-left|text-decoration\s*:\s*overline',
    caseSensitive: false,
  );
}

/// Keys on the three drawn parts. Notation is geometry — a bar the width of the
/// screen or a matrix with no brackets is still a widget that builds without
/// complaint — so the tests measure the real thing rather than trusting that it
/// was constructed.
const fractionBarKey = Key('question-math-fraction-bar');
const matrixKey = Key('question-math-matrix');
const overlineKey = Key('question-math-overline');
const figureKey = Key('question-math-figure');

enum _MathKind { fraction, matrix, overline, figure }

_MathKind? _kindOf(dom.Element element) {
  final style = element.attributes['style'] ?? '';
  switch (element.localName) {
    // A figure needs no inspection: an `<svg>` in a question is always one, and
    // `HtmlWidget` would otherwise walk into it and render its `<text>` labels
    // as loose words where the drawing should be.
    case 'svg':
      return _MathKind.figure;
    case 'table':
      // Brackets down both sides is a matrix; a bar under the top cell is a
      // fraction. Checked in that order because a matrix cell may itself hold a
      // fraction, and the outer table must not be mistaken for one.
      if (style.contains('border-left') && style.contains('border-right')) {
        return _MathKind.matrix;
      }
      final rows = _rowsOf(element);
      if (rows.length == 2 &&
          rows.every((r) => r.length == 1) &&
          (rows.first.first.attributes['style'] ?? '').contains('border-bottom')) {
        return _MathKind.fraction;
      }
      return null;
    case 'span':
      // An overline span is only worth taking over when it wraps something
      // HtmlWidget cannot underline for us — a nested table. Plain text keeps
      // the native text decoration, which aligns better with the line.
      if (!style.contains('text-decoration') || !style.contains('overline')) {
        return null;
      }
      return element.getElementsByTagName('table').isEmpty
          ? null
          : _MathKind.overline;
    default:
      return null;
  }
}

/// The cells of each row, skipping whatever `<tbody>` the parser inserted.
List<List<dom.Element>> _rowsOf(dom.Element table) => table
    .getElementsByTagName('tr')
    // Only this table's own rows: a fraction nested in a matrix cell has rows
    // of its own, and they belong to it.
    .where((tr) => _nearestTable(tr) == table)
    .map((tr) => tr.children.where((c) => c.localName == 'td' || c.localName == 'th').toList())
    .toList();

dom.Element? _nearestTable(dom.Element el) {
  var parent = el.parent;
  while (parent != null) {
    if (parent.localName == 'table') return parent;
    parent = parent.parent;
  }
  return null;
}

/// One cell, rendered with the same rules as the question around it — so a
/// fraction inside a matrix cell, or inside a radical, draws correctly too.
class _Cell extends StatelessWidget {
  const _Cell({required this.html, required this.style});

  final String html;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Inside notation the text sets tight. The extra leading a question line
    // carries is there to keep consecutive fractions apart; applied again to a
    // numerator it would just make the fraction tall and loose.
    final tight = style.copyWith(height: 1.15);

    // `HtmlWidget` is a block: left alone it takes every pixel of width offered,
    // which for a cell means the whole screen — a two-character numerator would
    // stretch the fraction across the page and push the sentence onto the next
    // line. `IntrinsicWidth` sizes it to its content, as a table cell does.
    return IntrinsicWidth(
      child: HtmlWidget(
        html,
        textStyle: tight,
        customWidgetBuilder: (element) => QuestionMath.build(element, style: tight),
        onTapUrl: (_) async => true,
      ),
    );
  }
}

/// `3x + 5` over `(x + 1)(x + 2)`, with the bar between them.
class _Fraction extends StatelessWidget {
  const _Fraction({required this.element, required this.style});

  final dom.Element element;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final rows = _rowsOf(element);
    final colour = style.color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final numerator = rows.first.first;
    final denominator = rows.last.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // The bar has no width of its own, so on `stretch` it takes the column's
      // — and `IntrinsicWidth` makes that the wider of the two rows rather than
      // the whole screen, which is what a browser draws and what keeps the
      // fraction inside the sentence it belongs to.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Center(child: _Cell(html: numerator.innerHtml, style: style)),
            ),
            Container(
              key: fractionBarKey,
              height: 1.4,
              color: colour,
              margin: const EdgeInsets.symmetric(vertical: 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Center(child: _Cell(html: denominator.innerHtml, style: style)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bracketed grid. The brackets are the table's own left and right borders,
/// rounded by `border-radius: 8px/50%` — an ellipse, which is why they read as
/// brackets rather than as a box with two sides missing.
class _Matrix extends StatelessWidget {
  const _Matrix({required this.element, required this.style});

  final dom.Element element;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final rows = _rowsOf(element);
    final colour = style.color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final side = BorderSide(color: colour, width: 1.6);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        key: matrixKey,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          border: Border(left: side, right: side),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.elliptical(8, 40),
            right: Radius.elliptical(8, 40),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final row in rows)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final cell in row)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      child: _Cell(html: cell.innerHtml, style: style),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A drawing inside a question: a circle theorem, a bar chart, a solid.
///
/// Two things it has to get right that a plain `SvgPicture` would not.
///
/// **Colour.** The bank draws for paper — `stroke="#000"` on white, and white
/// labels on coloured pie sectors. The exam screen is dark, where the strokes
/// disappear and the labels do not, so inverting would rescue the strokes and
/// lose the labels. The figure therefore keeps the light surface it was drawn
/// against, in both themes, and reads exactly like the past paper it came from.
/// The web stylesheet does the same.
///
/// **Size.** A figure is authored at whatever size suited the page, which may
/// be wider than a phone. It is drawn at its own size when it fits and scaled
/// down by its aspect ratio when it does not — never stretched up, because a
/// small figure blown across the screen is as unreadable as a clipped one.
class _Figure extends StatelessWidget {
  const _Figure({required this.element});

  final dom.Element element;

  /// The card's padding, the option row's letter bubble, and the surface's own
  /// margin. Measured off the screen rather than the constraints because a
  /// `LayoutBuilder` inside an inline span cannot answer an intrinsic-width
  /// query, and a fraction's cell asks for one.
  static const _chrome = 96.0;

  @override
  Widget build(BuildContext context) {
    final room = MediaQuery.sizeOf(context).width - _chrome;
    final drawn = _size(element, room);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        key: figureKey,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SvgPicture.string(
          element.outerHtml,
          width: drawn.width,
          height: drawn.height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// The size to draw [element] at, given the [room] available.
///
/// `width`/`height` are the authored size and the `viewBox` is the fallback —
/// a figure with neither cannot be measured, so it takes the width it is
/// offered at the 3:2 the bank's diagrams are drawn to.
Size _size(dom.Element element, double room) {
  final width = _lengthOf(element.attributes['width']);
  final height = _lengthOf(element.attributes['height']);
  final box = (element.attributes['viewBox'] ?? element.attributes['viewbox'] ?? '')
      .trim()
      .split(RegExp(r'[\s,]+'))
      .map(double.tryParse)
      .toList();

  final natural = (width != null && height != null)
      ? Size(width, height)
      : (box.length == 4 && box[2] != null && box[3] != null && box[2]! > 0 && box[3]! > 0)
          ? Size(box[2]!, box[3]!)
          : Size(room, room * 2 / 3);

  final safeRoom = room > 40 ? room : 40.0;
  if (natural.width <= safeRoom) return natural;
  return Size(safeRoom, safeRoom * natural.height / natural.width);
}

/// `"200"`, `"200px"` and `"200.5"` are all 200-odd pixels; `"100%"` is not a
/// measurement this can use, and falls through to the `viewBox`.
double? _lengthOf(String? raw) {
  if (raw == null || raw.contains('%')) return null;
  final value = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  return (value != null && value > 0) ? value : null;
}

/// The radicand under a surd — a rule stretched across whatever it contains,
/// including a fraction, which a text decoration could not reach.
class _Overline extends StatelessWidget {
  const _Overline({required this.element, required this.style});

  final dom.Element element;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final colour = style.color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        key: overlineKey,
        padding: const EdgeInsets.only(top: 1.5),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colour, width: 1.4)),
        ),
        child: _Cell(html: element.innerHtml, style: style),
      ),
    );
  }
}

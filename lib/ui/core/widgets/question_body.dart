import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../domain/models/question.dart';
import '../theme/app_palette.dart';
import 'question_math.dart';

/// Renders a question's text, and its diagram when it has one.
///
/// Question text is HTML, not plain text: the admin uploader accepts rich text,
/// and real past questions lean on it — `<sup>` for indices, `<sub>` for chemical
/// formulae, `<em>` for the passages in a comprehension. The web renders it with
/// `dangerouslySetInnerHTML`; rendering it as plain text here would show a
/// student `H<sub>2</sub>O` instead of H₂O, so the same markup goes through an
/// HTML widget with an allowlist over it.
///
/// Maths papers go further: a fraction, a matrix and a surd are drawn with
/// inline CSS the HTML widget cannot lay out, so [QuestionMath] takes those
/// three over and draws them as real widgets. See that file for why.
class QuestionBody extends StatelessWidget {
  const QuestionBody({
    super.key,
    required this.question,
    this.selectable = false,
    this.fontSize = 17,
  });

  final Question question;

  /// True on the review screen, where there is no PageView for a selection
  /// gesture to fight with.
  final bool selectable;

  final double fontSize;

  /// Tags dropped rather than rendered. Question text comes from an admin
  /// console, but it is still content flowing into the app, and none of these
  /// have any business in a question.
  static const _blocked = {'script', 'iframe', 'object', 'embed', 'form'};

  /// True when [html] contains markup worth handing to the HTML renderer.
  ///
  /// Most questions are plain prose, and a plain [Text] both renders faster and
  /// keeps text selection working, so the heavier path is only taken when it
  /// actually buys something.
  static bool hasMarkup(String html) => _tag.hasMatch(html);
  static final _tag = RegExp(r'<[a-zA-Z/!][^>]*>|&[a-zA-Z#][a-zA-Z0-9]*;');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: fontSize,
          height: 1.55,
          fontWeight: FontWeight.w600,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichQuestionText(
          html: question.text,
          style: style,
          selectable: selectable,
        ),
        if (question.imageUrl != null) ...[
          const SizedBox(height: Tokens.s4),
          ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.rSm),
            child: Image.network(
              question.imageUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 160,
                      color: scheme.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
              // A diagram that won't load offline must say so: a student staring
              // at a blank space would read the question as broken and skip it.
              errorBuilder: (context, _, _) => Container(
                padding: const EdgeInsets.all(Tokens.s4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Tokens.s3),
                    Expanded(
                      child: Text(
                        'This question has a diagram that needs a connection to '
                        'load.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One run of question or option markup.
class RichQuestionText extends StatelessWidget {
  const RichQuestionText({
    super.key,
    required this.html,
    this.style,
    this.selectable = false,
  });

  final String html;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (!QuestionBody.hasMarkup(html)) {
      return selectable
          ? SelectableText(html, style: style)
          : Text(html, style: style);
    }

    // Notation stands two lines tall. Without the extra leading, a fraction on
    // one line touches the fraction on the next; ordinary prose keeps the
    // tighter setting it was given.
    final base = style ?? const TextStyle();
    final effective = QuestionMath.hasNotation(html)
        ? base.copyWith(height: (base.height ?? 1.4) + 0.35)
        : base;

    return HtmlWidget(
      html,
      textStyle: effective,
      customWidgetBuilder: (element) {
        if (QuestionBody._blocked.contains(element.localName)) {
          return const SizedBox.shrink();
        }
        return QuestionMath.build(element, style: effective);
      },
      // Nothing in a question should navigate anywhere.
      onTapUrl: (_) async => true,
    );
  }
}

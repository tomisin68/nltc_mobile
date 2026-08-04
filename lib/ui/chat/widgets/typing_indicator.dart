import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// The three bouncing dots at the foot of a conversation.
///
/// Sits where the next message will land rather than in the app bar, because
/// that is the question it answers — not "is someone typing" but "is the reply
/// I am waiting for about to appear here". The web draws it as a bubble in the
/// thread for the same reason, and this matches it.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.names});

  /// Display names of everyone typing, already filtered to exclude this student.
  final List<String> names;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// "Ada is typing…", "Ada & Chidi are typing…", "3 people are typing…".
  String get _label {
    final names = widget.names.map(_firstName).toList();
    return switch (names.length) {
      0 => 'Typing…',
      1 => '${names.first} is typing…',
      2 => '${names[0]} & ${names[1]} are typing…',
      _ => '${names.length} people are typing…',
    };
  }

  static String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Someone';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      label: _label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s2),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Tokens.rMd),
                topRight: Radius.circular(Tokens.rMd),
                bottomRight: Radius.circular(Tokens.rMd),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _Dot(controller: _controller, index: i, color: scheme.primary),
                ],
                const SizedBox(width: Tokens.s2),
                Text(
                  _label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.controller,
    required this.index,
    required this.color,
  });

  final AnimationController controller;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          // Each dot a third of a cycle behind the last, so the three read as one
          // wave rather than three separate blinks.
          final phase = (controller.value + index / 3) % 1.0;
          final lift = (phase < 0.5 ? phase : 1 - phase) * 2;
          return Transform.translate(
            offset: Offset(0, -3 * lift),
            child: Opacity(opacity: 0.45 + 0.55 * lift, child: child),
          );
        },
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_palette.dart';

/// The overlay shown when a student leaves an exam.
///
/// Port of the `AntiCheatWarning` component duplicated in `QuickTestsView.jsx`,
/// `NLTCQuizView.jsx` and `CBTPage.jsx` — one copy here, since all three show the
/// identical panel.
class AntiCheatWarning extends StatelessWidget {
  const AntiCheatWarning({
    super.key,
    required this.violations,
    required this.maxViolations,
    required this.isFinal,
    this.onDismiss,
  });

  final int violations;
  final int maxViolations;

  /// True on the last strike — the exam has already submitted itself, so there
  /// is nothing to dismiss back to.
  final bool isFinal;

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = maxViolations - violations;

    return Positioned.fill(
      child: ColoredBox(
        color: BlueprintPalette.ink.withValues(alpha: 0.72),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Tokens.s5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(Tokens.rXl),
                ),
                padding: const EdgeInsets.all(Tokens.s6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.errorContainer,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isFinal
                            ? Icons.block_rounded
                            : Icons.warning_amber_rounded,
                        size: 28,
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(height: Tokens.s4),
                    Text(
                      isFinal ? 'Test Auto-Submitted' : 'You Left the Test',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isFinal
                          ? 'You have left the test too many times. Your '
                              'answers have been submitted automatically.'
                          : 'Leaving the test is not allowed. This is violation '
                              '$violations of $maxViolations.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (!isFinal) ...[
                      const SizedBox(height: Tokens.s3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 14,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '$remaining warning'
                              '${remaining == 1 ? '' : 's'} remaining before '
                              'auto-submit.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Tokens.s5),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onDismiss,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                          label: const Text('Return to Test'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

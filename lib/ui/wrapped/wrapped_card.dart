import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/wrapped_stats.dart';
import '../core/theme/app_palette.dart';

/// The card a student shares.
///
/// Fixed at [width] × [height] in logical pixels regardless of the phone it is
/// drawn on, because this widget is also the thing that gets captured to a PNG
/// — a card that reflowed on a small screen would be shared looking different
/// from the one the student was shown. 4:5 is the portrait crop that survives
/// WhatsApp, Instagram and X without any of them cutting the numbers off.
///
/// Callers must give it the size it asks for and scale the result, rather than
/// handing it a narrower box: see `_CardPanel` in `wrapped_screen.dart`.
class WrappedCard extends StatelessWidget {
  const WrappedCard({
    super.key,
    required this.stats,
    required this.name,
  });

  static const width = 340.0;
  static const height = 425.0;

  final WrappedStats stats;

  /// First name only — a shared card is a public object.
  final String name;

  @override
  Widget build(BuildContext context) {
    final top = stats.topSubject;

    // The card's height is fixed but its type was not, so a student with the
    // system font size turned up grew the column past the bottom edge and the
    // shared PNG came out with its last line sliced in half. Nothing in here is
    // body copy the OS setting needs to reach — it is a picture, and it has to
    // measure the same on every phone or the capture cannot be trusted.
    return MediaQuery.withNoTextScaling(
      child: _build(top),
    );
  }

  Widget _build(SubjectTally? top) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BlueprintPalette.b800,
            BlueprintPalette.ink,
            BlueprintPalette.b900,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          // A wash of brand blue behind the headline, so the card has a focal
          // point that survives being scaled down to a chat thumbnail.
          Positioned(
            top: -70,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x551D6FF2), Color(0x001D6FF2)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/nltc-light.png',
                      height: 22,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'WRAPPED',
                        style: GoogleFonts.syne(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: BlueprintPalette.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  stats.monthLabel.toUpperCase(),
                  style: GoogleFonts.syne(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: BlueprintPalette.b300,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stats.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                    fontSize: 32,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: BlueprintPalette.white,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  stats.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: BlueprintPalette.b200,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Stat(
                      value: '${stats.questions}',
                      label: 'questions',
                    ),
                    _Stat(
                      value: '${stats.accuracy}%',
                      label: 'accuracy',
                    ),
                    _Stat(
                      value: '${stats.activeDays}',
                      label: stats.activeDays == 1 ? 'day' : 'days',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Stat(
                      value: '${stats.sittings}',
                      label: stats.sittings == 1 ? 'test' : 'tests',
                    ),
                    _Stat(
                      value: stats.bestScore == 0 ? '—' : '${stats.bestScore}%',
                      label: 'best score',
                    ),
                    _Stat(
                      value: stats.timeStudied == null
                          ? '${stats.streak}'
                          : WrappedStats.formatDuration(stats.timeStudied!),
                      label: stats.timeStudied == null ? 'day streak' : 'studied',
                    ),
                  ],
                ),
                const Spacer(),
                if (top != null) ...[
                  Text(
                    'MOST PRACTISED',
                    style: GoogleFonts.syne(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: BlueprintPalette.b300,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${top.subject} · ${top.questions} questions · ${top.accuracy}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BlueprintPalette.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  height: 1,
                  color: const Color(0x26FFFFFF),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'An NLTC student' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: BlueprintPalette.white,
                        ),
                      ),
                    ),
                    Text(
                      'nltc.com.ng',
                      style: GoogleFonts.syne(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: BlueprintPalette.b300,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One number and its caption.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(Tokens.rSm),
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  // Syne's numerals are a display shape — at 19px, scaled down
                  // to a chat thumbnail, its 8 and 0 stopped being separable.
                  // DM Sans is what the rest of the app counts in.
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: BlueprintPalette.white,
                    // Tabular, so the three boxes in a row line up as a grid
                    // rather than as three unrelated numbers.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: BlueprintPalette.b300,
                ),
              ),
            ],
          ),
        ),
      );
}

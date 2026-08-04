import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../data/services/prefs_service.dart';
import '../theme/app_palette.dart';

/// Pomodoro chip that lives in the topbar, so a focus block keeps running while
/// the student moves between views.
///
/// Port of `src/components/ui/FocusTimer.jsx`. The session is persisted as a
/// wall-clock end time rather than a countdown, which is what lets it survive
/// the app being backgrounded — a phone that suspends the isolate gets no timer
/// callbacks, but the end time is still true when it wakes.
class FocusTimer extends StatefulWidget {
  const FocusTimer({super.key});

  @override
  State<FocusTimer> createState() => _FocusTimerState();
}

class _FocusTimerState extends State<FocusTimer> with WidgetsBindingObserver {
  /// The blocks offered as one tap, in minutes.
  ///
  /// More than the web's three, and laid out as a grid rather than a row of
  /// equal thirds: a student revising one topic wants ten minutes and one
  /// revising a whole paper wants ninety, and neither should have to settle for
  /// twenty-five. Anything not on the list is reachable with the steppers.
  static const _presets = <int>[5, 10, 15, 20, 25, 30, 45, 60, 90];

  /// The range the steppers move within, and the step they move by.
  static const _minMinutes = 1;
  static const _maxMinutes = 180;
  static const _step = 5;

  Timer? _ticker;

  /// Total length of the current session, in seconds.
  int? _duration;

  /// When the running session ends. Null while paused or idle.
  DateTime? _endsAt;

  /// Seconds left in a paused session. Null unless paused.
  int? _pausedLeft;

  int _preset = 25;

  bool get _running => _endsAt != null;
  bool get _paused => _duration != null && _endsAt == null;
  bool get _idle => _duration == null;

  int get _remaining {
    if (_running) {
      final secs = _endsAt!.difference(DateTime.now()).inSeconds;
      return secs > 0 ? secs : 0;
    }
    if (_paused) return _pausedLeft ?? 0;
    return _preset * 60;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  /// A session that ran out while the app was backgrounded is only noticed here.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running && _remaining == 0) {
      _complete();
    }
  }

  void _restore() {
    final prefs = context.read<PrefsService>();
    _preset = prefs.focusPreset.clamp(_minMinutes, _maxMinutes);

    final saved = prefs.focusSession;
    if (saved == null) return;

    final dur = saved['dur'];
    if (dur is! num) return;

    final end = saved['end'];
    if (end is num) {
      final endsAt = DateTime.fromMillisecondsSinceEpoch(end.toInt());
      // A session that already elapsed while the app was closed is dropped
      // rather than resumed at zero — the moment to celebrate it has passed.
      if (!endsAt.isAfter(DateTime.now())) {
        unawaited(context.read<PrefsService>().setFocusSession(null));
        return;
      }
      _duration = dur.toInt();
      _endsAt = endsAt;
      _startTicker();
      return;
    }

    final left = saved['left'];
    if (left is num) {
      _duration = dur.toInt();
      _pausedLeft = left.toInt();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 0) {
        _complete();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _persist() async {
    final prefs = context.read<PrefsService>();
    if (_idle) return prefs.setFocusSession(null);
    if (_running) {
      return prefs.setFocusSession({
        'dur': _duration,
        'end': _endsAt!.millisecondsSinceEpoch,
      });
    }
    return prefs.setFocusSession({'dur': _duration, 'left': _pausedLeft});
  }

  void _start() {
    final duration = _paused ? _duration! : _preset * 60;
    final left = _paused ? (_pausedLeft ?? duration) : duration;
    setState(() {
      _duration = duration;
      _endsAt = DateTime.now().add(Duration(seconds: left));
      _pausedLeft = null;
    });
    _startTicker();
    unawaited(_persist());
  }

  void _pause() {
    final left = _remaining;
    _ticker?.cancel();
    setState(() {
      _pausedLeft = left;
      _endsAt = null;
    });
    unawaited(_persist());
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _duration = null;
      _endsAt = null;
      _pausedLeft = null;
    });
    unawaited(_persist());
  }

  void _complete() {
    final minutes = (_duration ?? 0) ~/ 60;
    _reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Focus session done — $minutes minutes of deep work. '
          'Take a short break! 🧠',
        ),
      ),
    );
  }

  static String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final remaining = _remaining;
    final duration = _duration ?? _preset * 60;

    // Fraction still to run — the ring depletes as the block is used up.
    final left = duration == 0 ? 0.0 : (remaining / duration).clamp(0.0, 1.0);

    final Color background;
    final Color foreground;
    final Color? border;
    if (_running) {
      background = BlueprintPalette.b600;
      foreground = BlueprintPalette.white;
      border = null;
    } else if (_paused) {
      background = isDark ? scheme.surfaceContainerHigh : BlueprintPalette.b100;
      foreground = isDark ? scheme.onSurface : BlueprintPalette.b700;
      border = BlueprintPalette.b300;
    } else {
      background = isDark ? scheme.surfaceContainerLow : BlueprintPalette.white;
      foreground = scheme.onSurfaceVariant;
      border = scheme.outline;
    }

    return Semantics(
      button: true,
      label: _idle ? 'Focus timer' : 'Focus timer, ${_fmt(remaining)} remaining',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: _openSheet,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: border == null
                  ? null
                  : Border.all(color: border, width: 1.5),
              gradient: _running
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [BlueprintPalette.b600, BlueprintPalette.b500],
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_idle)
                  Icon(Icons.timer_outlined, size: 14, color: foreground)
                else
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CustomPaint(
                      painter: _RingPainter(fraction: left, color: foreground),
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  _idle ? 'Focus' : _fmt(remaining),
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                    // Tabular figures so the countdown doesn't jitter as digits
                    // change width.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (_paused) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.pause_rounded, size: 11, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The web anchors a popover under the chip. A bottom sheet is the phone
  /// equivalent — a 250px popover pinned to the top-right corner of a handset is
  /// both cramped and awkward to reach.
  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _FocusSheet(
        remaining: _remaining,
        idle: _idle,
        running: _running,
        paused: _paused,
        preset: _preset,
        presets: _presets,
        minMinutes: _minMinutes,
        maxMinutes: _maxMinutes,
        step: _step,
        onPreset: _choosePreset,
        onStart: () {
          _start();
          Navigator.of(sheetContext).pop();
        },
        onPause: _pause,
        onReset: () {
          _reset();
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  void _choosePreset(int minutes) {
    final chosen = minutes.clamp(_minMinutes, _maxMinutes);
    setState(() => _preset = chosen);
    unawaited(context.read<PrefsService>().setFocusPreset(chosen));
  }
}

/// The depleting progress ring on the chip.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.color});

  /// How much of the block is still to run, 0..1.
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2 - 1.25;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.25);
    canvas.drawCircle(centre, radius, track);

    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// The picker and the controls.
///
/// Stateful, and holding its own copy of the chosen block, because a modal
/// route does not rebuild when the widget that opened it calls `setState`. The
/// chip taps were reaching the timer perfectly well — they simply left no mark
/// on the sheet the student was looking at, so every block but the one already
/// selected felt like a dead button.
class _FocusSheet extends StatefulWidget {
  const _FocusSheet({
    required this.remaining,
    required this.idle,
    required this.running,
    required this.paused,
    required this.preset,
    required this.presets,
    required this.minMinutes,
    required this.maxMinutes,
    required this.step,
    required this.onPreset,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  final int remaining;
  final bool idle;
  final bool running;
  final bool paused;
  final int preset;
  final List<int> presets;
  final int minMinutes;
  final int maxMinutes;
  final int step;
  final ValueChanged<int> onPreset;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;

  @override
  State<_FocusSheet> createState() => _FocusSheetState();
}

class _FocusSheetState extends State<_FocusSheet> {
  late int _minutes = widget.preset;

  void _choose(int minutes) {
    final chosen = minutes.clamp(widget.minMinutes, widget.maxMinutes);
    if (chosen == _minutes) return;
    setState(() => _minutes = chosen);
    widget.onPreset(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // While idle the big number is the block being chosen, so it answers the
    // chips as they are tapped rather than sitting on whatever was set last.
    final shown = widget.idle ? _minutes * 60 : widget.remaining;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s2,
          Tokens.s5,
          Tokens.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 15, color: scheme.primary),
                const SizedBox(width: 7),
                Text(
                  'Focus timer',
                  style: GoogleFonts.fraunces(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s3),

            // The clock, with a stepper either side of it while idle: the range
            // is wider than any list of chips, and nudging the number is the
            // shortest path to a block nobody thought to offer.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.idle)
                  _StepButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'Less time',
                    onTap: _minutes <= widget.minMinutes
                        ? null
                        : () => _choose(
                              _minutes <= widget.step
                                  ? widget.minMinutes
                                  // Snap to the step rather than sliding off it,
                                  // so 27 goes to 25 and not 22.
                                  : (_minutes - 1) ~/ widget.step * widget.step,
                            ),
                  ),
                Expanded(
                  child: Text(
                    _FocusTimerState._fmt(shown),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (widget.idle)
                  _StepButton(
                    icon: Icons.add_rounded,
                    tooltip: 'More time',
                    onTap: _minutes >= widget.maxMinutes
                        ? null
                        : () => _choose(
                              (_minutes ~/ widget.step + 1) * widget.step,
                            ),
                  ),
              ],
            ),

            if (widget.idle) ...[
              const SizedBox(height: Tokens.s4),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: [
                  for (final minutes in widget.presets)
                    _PresetChip(
                      minutes: minutes,
                      selected: _minutes == minutes,
                      onTap: () => _choose(minutes),
                    ),
                ],
              ),
              const SizedBox(height: Tokens.s4),
            ],

            Row(
              children: [
                if (widget.idle)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text('Start $_minutes min'),
                    ),
                  ),
                if (widget.running)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onPause,
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: const Text('Pause'),
                    ),
                  ),
                if (widget.paused)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Resume'),
                    ),
                  ),
                if (!widget.idle) ...[
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onReset,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reset'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Tokens.s3),
            Text(
              'Pick a block, start, then go practise. The timer keeps running '
              "while you study — we'll let you know when time's up.",
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two nudges either side of the clock.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton.outlined(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(
          Tokens.minTouchTarget,
          Tokens.minTouchTarget,
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: Tokens.minTouchTarget,
          // Wide enough to be an easy target on its own, and sized to its label
          // so the row of them wraps rather than squeezing.
          constraints: const BoxConstraints(minWidth: 74),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                '$minutes min',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

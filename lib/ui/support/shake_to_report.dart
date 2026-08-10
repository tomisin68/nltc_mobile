import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'bug_report_sheet.dart';

/// Listens for a shake anywhere in the app and offers to file a bug report.
///
/// Wrapped around the whole signed-in app rather than bolted onto a screen,
/// because the moment worth reporting is the moment something looked wrong —
/// and that is never on the page with the feedback button on it. A student who
/// sees a blank lesson, a stuck exam timer or a chat that will not send can
/// shake the phone right there and describe what they are looking at, while
/// they are still looking at it.
class ShakeToReport extends StatefulWidget {
  const ShakeToReport({super.key, required this.child});

  final Widget child;

  @override
  State<ShakeToReport> createState() => _ShakeToReportState();
}

class _ShakeToReportState extends State<ShakeToReport> {
  StreamSubscription<AccelerometerEvent>? _subscription;

  /// Metres per second squared past gravity. Tuned high enough that carrying a
  /// phone downstairs or dropping it into a bag doesn't trip it — a deliberate
  /// shake clears 15 easily, ordinary handling sits well under 12.
  static const _threshold = 15.0;

  /// How many jolts past [_threshold], inside [_window], count as a shake.
  /// One spike is a bump; three is somebody shaking a phone on purpose.
  static const _requiredJolts = 3;
  static const _window = Duration(milliseconds: 1200);

  /// Silence after a shake is handled, so the sheet cannot be opened twice by
  /// one continuous shake — and so declining it doesn't immediately re-prompt.
  static const _cooldown = Duration(seconds: 3);

  final _jolts = <DateTime>[];
  DateTime? _lastPrompt;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    // A device with no accelerometer (an emulator, a desktop build) simply
    // never emits — the feature goes quiet rather than failing.
    _subscription = accelerometerEventStream().listen(
      _onSample,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onSample(AccelerometerEvent event) {
    if (_sheetOpen) return;

    final force = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (force < _threshold) return;

    final now = DateTime.now();
    if (_lastPrompt != null && now.difference(_lastPrompt!) < _cooldown) return;

    _jolts
      ..add(now)
      ..removeWhere((t) => now.difference(t) > _window);

    if (_jolts.length < _requiredJolts) return;

    _jolts.clear();
    _lastPrompt = now;
    _prompt();
  }

  Future<void> _prompt() async {
    if (!mounted || _sheetOpen) return;
    _sheetOpen = true;
    try {
      await showBugReportSheet(context);
    } finally {
      _sheetOpen = false;
      _lastPrompt = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

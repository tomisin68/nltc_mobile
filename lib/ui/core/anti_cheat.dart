import 'package:flutter/material.dart';

/// Watches for a student leaving an exam mid-sitting.
///
/// Port of `src/hooks/useAntiCheat.js`. The web's signal is
/// `visibilitychange` — a tab switch; the phone equivalent is the app losing the
/// foreground, which is what happens when a student switches apps to look
/// something up. Both mean the same thing and are counted the same way.
///
/// The web also blocks right-click, copy/cut and dev-tool shortcuts. Those have
/// no counterpart here: text selection is off by default in the exam UI, and
/// there is no dev console to open. What survives the port is the part that
/// actually matters — leaving the exam is counted, and enough of it submits.
///
/// Mix into the [State] that owns the exam and call [startAntiCheat] once the
/// first question is on screen.
mixin AntiCheatObserver<T extends StatefulWidget> on State<T>
    implements WidgetsBindingObserver {
  int _violations = 0;
  bool _autoSubmitted = false;
  bool _armed = false;

  /// True while the student is away, so returning is what counts — not leaving.
  /// A phone can pause an app for a notification banner without the student
  /// going anywhere; counting only the return means a genuine switch away and
  /// back is one violation, not two.
  bool _away = false;

  /// How many times the student has left. Read by the warning overlay.
  int get antiCheatViolations => _violations;

  /// Whether the limit has been hit and the exam submitted itself.
  bool get antiCheatAutoSubmitted => _autoSubmitted;

  /// Violations allowed before [onAntiCheatAutoSubmit] fires. Both Quick Tests
  /// and the Official Quiz use 3 on the web.
  int get antiCheatMaxViolations => 3;

  /// Called on every violation, with the running count.
  void onAntiCheatViolation(int count);

  /// Called once, when the count reaches [antiCheatMaxViolations].
  void onAntiCheatAutoSubmit();

  /// Begins watching. Safe to call again — it resets the counters, which is what
  /// starting a second test in the same screen needs.
  void startAntiCheat() {
    if (!_armed) {
      WidgetsBinding.instance.addObserver(this);
      _armed = true;
    }
    _violations = 0;
    _autoSubmitted = false;
    _away = false;
  }

  /// Stops watching. Called on submit, so the results screen isn't policed.
  void stopAntiCheat() {
    if (!_armed) return;
    WidgetsBinding.instance.removeObserver(this);
    _armed = false;
  }

  @override
  void dispose() {
    stopAntiCheat();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_armed) return;

    switch (state) {
      // `inactive` also fires for a transient overlay — a call banner, the
      // notification shade — so only a real background counts as leaving.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _away = true;
      case AppLifecycleState.resumed:
        if (!_away) return;
        _away = false;
        _recordViolation();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _recordViolation() {
    _violations++;
    onAntiCheatViolation(_violations);
    if (_violations >= antiCheatMaxViolations && !_autoSubmitted) {
      _autoSubmitted = true;
      onAntiCheatAutoSubmit();
    }
  }
}

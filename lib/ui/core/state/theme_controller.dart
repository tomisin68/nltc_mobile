import 'package:flutter/material.dart';

import '../../../data/services/prefs_service.dart';

/// Holds the chosen theme mode and writes it straight back to [PrefsService].
///
/// The mode is read synchronously at startup, so the very first frame is
/// already in the right brightness — no flash of light theme on a dark phone.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) : _mode = _prefs.themeMode;

  final PrefsService _prefs;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    // Repaint first, persist second — the toggle should never wait on disk.
    notifyListeners();
    await _prefs.setThemeMode(mode);
  }

  /// system → light → dark → system. What the app-bar toggle calls.
  Future<void> cycle() => setMode(switch (_mode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      });

  /// Icon and label for the *current* mode, for the toggle button.
  (IconData, String) get indicator => switch (_mode) {
        ThemeMode.system => (Icons.brightness_auto_outlined, 'System theme'),
        ThemeMode.light => (Icons.light_mode_outlined, 'Light theme'),
        ThemeMode.dark => (Icons.dark_mode_outlined, 'Dark theme'),
      };
}

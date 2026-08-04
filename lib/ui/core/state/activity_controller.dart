import 'package:flutter/foundation.dart';

import '../../../data/repositories/attempt_repository.dart';
import '../../../domain/models/exam_attempt.dart';

/// The student's attempt history, shared by the dashboard and the activity tab.
///
/// Held above both so a sitting finished on one surface is visible on the other
/// without either screen polling — the result screen calls [reload] once, and
/// everything watching updates.
class ActivityController extends ChangeNotifier {
  ActivityController(this._attempts);

  final AttemptRepository _attempts;

  List<ExamAttempt> _items = const [];
  bool _loading = true;
  bool _syncing = false;

  List<ExamAttempt> get items => _items;
  bool get isLoading => _loading;
  bool get isSyncing => _syncing;
  bool get isEmpty => _items.isEmpty && !_loading;

  int get pendingCount =>
      _items.where((a) => a.syncState != SyncState.synced).length;

  /// Mean score across every saved sitting, 0 when there are none.
  double get averageScore => _items.isEmpty
      ? 0
      : _items.map((a) => a.score).reduce((a, b) => a + b) / _items.length;

  List<ExamAttempt> take(int count) => _items.take(count).toList();

  Future<void> reload() async {
    _items = await _attempts.recent();
    _loading = false;
    notifyListeners();
  }

  /// Pushes the queue, then reloads so the sync icons on each row are current.
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      await _attempts.syncPending();
    } finally {
      _syncing = false;
      await reload();
    }
  }
}

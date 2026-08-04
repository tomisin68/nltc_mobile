import 'package:intl/intl.dart';

/// Small display formatters shared across screens.
///
/// Kept here rather than in a model: these are how a value is *shown*, and the
/// same attempt or notification is rendered by more than one screen.

/// "Just now" / "3h ago" / "12 Mar" — the shape a student reads at a glance.
String relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat(diff.inDays > 330 ? 'd MMM yyyy' : 'd MMM').format(when);
}

/// "Last seen 14:32" / "Last seen yesterday" — the status under a name in a chat.
///
/// Deliberately vaguer the further back it goes: the exact minute someone was
/// last on three weeks ago is not information, it is surveillance.
String lastSeenLabel(DateTime? when) {
  if (when == null) return 'Offline';

  final now = DateTime.now();
  final diff = now.difference(when);
  if (diff.inMinutes < 1) return 'Last seen just now';
  if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';

  final sameDay =
      when.year == now.year && when.month == now.month && when.day == now.day;
  if (sameDay) return 'Last seen ${DateFormat('HH:mm').format(when)}';

  final yesterday = now.subtract(const Duration(days: 1));
  final wasYesterday = when.year == yesterday.year &&
      when.month == yesterday.month &&
      when.day == yesterday.day;
  if (wasYesterday) {
    return 'Last seen yesterday at ${DateFormat('HH:mm').format(when)}';
  }
  if (diff.inDays < 7) return 'Last seen ${DateFormat('EEEE').format(when)}';
  return 'Last seen ${DateFormat('d MMM').format(when)}';
}

/// "12 Mar 2026" — the web's `formatDate`, used in history and payment tables.
///
/// Returns an em dash for a missing date rather than an empty cell, so a table
/// row never looks truncated.
String formatDate(DateTime? when) =>
    when == null ? '—' : DateFormat('d MMM yyyy').format(when);

/// "15 March 2026" — the long form used in the fee and access copy.
String formatLongDate(DateTime? when) =>
    when == null ? '—' : DateFormat('d MMMM y').format(when);

/// Thousands separators: `1234` → `1,234`.
///
/// Matches JavaScript's `toLocaleString()` for the integers this app shows — XP
/// totals and naira amounts.
String thousands(num value) => NumberFormat.decimalPattern().format(value);

/// `₦2,000` — money, always whole naira, as every price on the platform is.
String naira(num amount) => '₦${thousands(amount.round())}';

/// Elapsed time on an attempt: `45s`, `12m 30s`, `1h 05m`.
String formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

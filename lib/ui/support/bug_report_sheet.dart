import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../data/services/api_client.dart';
import '../core/state/dashboard_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';

/// The bug report form, opened from the support sheet.
///
/// Separate from a support conversation on purpose: this one is a filing, not a
/// chat. Nobody replies, and in exchange the student writes one paragraph
/// instead of waiting on an admin.
///
/// Everything below the message box is collected rather than asked for. A
/// student reporting "the lesson wouldn't play" has no idea what build they are
/// on, and asking would both lose the report and get the answer wrong.
Future<void> showBugReportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BugReportSheet(),
    );

class BugReportSheet extends StatefulWidget {
  const BugReportSheet({super.key});

  @override
  State<BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<BugReportSheet> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Build and device facts, gathered at send time.
  ///
  /// Best-effort throughout: a platform channel that fails must cost a field,
  /// never the report. A report with a missing device name is still a report.
  Future<Map<String, String>> _diagnostics() async {
    final out = <String, String>{};

    try {
      final info = await PackageInfo.fromPlatform();
      out['appVersion'] = '${info.version}+${info.buildNumber}';
    } catch (_) {/* keep going */}

    try {
      final device = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await device.androidInfo;
        out['platform'] = 'android';
        out['device'] = '${android.manufacturer} ${android.model}';
        out['osVersion'] = 'Android ${android.version.release} '
            '(SDK ${android.version.sdkInt})';
      } else if (Platform.isIOS) {
        final ios = await device.iosInfo;
        out['platform'] = 'ios';
        out['device'] = ios.utsname.machine;
        out['osVersion'] = '${ios.systemName} ${ios.systemVersion}';
      }
    } catch (_) {/* keep going */}

    return out;
  }

  Future<void> _submit() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    // Which screen they were on when they opened the form. More useful than
    // anything they are likely to type, and free to collect.
    final screen = context.read<DashboardController>().view.name;
    final api = context.read<ApiClient>();

    try {
      final diagnostics = await _diagnostics();
      await api.post('/reports/bug', {
        'message': text,
        'screen': screen,
        ...diagnostics,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Thank you — your report is with our team.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast('Could not send that report. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s4,
        Tokens.s5,
        Tokens.s4,
        insets + Tokens.s5,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: Tokens.s2),
                const Expanded(
                  child: Text(
                    'Something not working?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            Text(
              'Tell us what you were doing and what happened. The screen you '
              'came from, your app version and your device are attached '
              'automatically, so there is nothing to look up.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s4),
            TextField(
              controller: _message,
              autofocus: true,
              enabled: !_sending,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. I tapped Start on my Chemistry test and the '
                    'timer stayed at 00:00.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Tokens.s2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

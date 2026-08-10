import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/access_state.dart';
import '../core/state/practice_controller.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/message_banner.dart';
import '../core/widgets/notification_bell.dart';
import 'exam_setup_sheet.dart';

/// The subject catalogue: what can be practised, and what is already offline.
///
/// Downloaded subjects sort to the top, because a student on a metered
/// connection cares far more about what they can open right now than about
/// alphabetical order.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _download(String subject) async {
    final controller = context.read<PracticeController>();
    final messenger = ScaffoldMessenger.of(context);

    // Downloading a whole subject bank is the paid product sitting on the
    // device. An expired account can keep and re-read what it already has, but
    // it does not get to pull anything new down.
    final access = context.read<SessionController>().access;
    if (access.isLocked) {
      messenger.showSnackBar(SnackBar(content: Text(access.lockNote)));
      return;
    }

    final saved = await controller.download(subject);
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved == null
              ? 'Could not download $subject. Check your connection.'
              : saved == 0
                  ? 'No questions are published for $subject yet.'
                  : '$subject is ready — $saved questions saved for offline use.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PracticeController>();
    final subjects = controller.visible;
    final access = context.select<SessionController, AccessState>(
      (s) => s.access,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: const [NotificationBell(), SizedBox(width: 4)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s5,
                Tokens.s2,
                Tokens.s5,
                Tokens.s3,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: controller.search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search subjects',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            controller.search('');
                          },
                        ),
                ),
              ),
            ),
            if (access.isLocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s5,
                  0,
                  Tokens.s5,
                  Tokens.s3,
                ),
                child: MessageBanner(
                  message: access.lockNote,
                  tone: MessageTone.info,
                ),
              ),
            if (controller.downloadingSubject != null)
              _DownloadStrip(
                subject: controller.downloadingSubject!,
                fetched: controller.downloadedSoFar,
                total: controller.downloadTotal,
                fraction: controller.downloadFraction,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.load,
                child: _body(context, controller, subjects),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PracticeController controller,
    List<SubjectEntry> subjects,
  ) {
    if (controller.isLoading && subjects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (subjects.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: Tokens.s10),
          EmptyState(
            icon: controller.query.isEmpty
                ? Icons.cloud_off_outlined
                : Icons.search_off_outlined,
            title: controller.query.isEmpty
                ? 'No subjects available'
                : 'Nothing matches "${controller.query}"',
            message: controller.error ??
                (controller.query.isEmpty
                    ? 'Pull down to try again once you have a connection.'
                    : 'Try a different spelling, or clear the search.'),
            actionLabel: controller.query.isEmpty ? 'Try again' : null,
            onAction: controller.query.isEmpty ? controller.load : null,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Tokens.s5,
        Tokens.s2,
        Tokens.s5,
        Tokens.s10,
      ),
      itemCount: subjects.length,
      separatorBuilder: (_, _) => const SizedBox(height: Tokens.s3),
      // Locked accounts keep a live download button on purpose: tapping it
      // says why they cannot pull a new subject down, which a greyed-out
      // button never would.
      itemBuilder: (context, i) => SubjectCard(
        entry: subjects[i],
        busy: controller.downloadingSubject != null,
        onStart: () => showExamSetupSheet(context, subjects[i]),
        onDownload: () => _download(subjects[i].name),
        onDelete: subjects[i].isDownloaded
            ? () => _confirmDelete(subjects[i].name)
            : null,
      ),
    );
  }

  Future<void> _confirmDelete(String subject) async {
    final controller = context.read<PracticeController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $subject?'),
        content: const Text(
          'The questions will be deleted from this device. Your past attempts '
          'and scores are not affected, and you can download the subject '
          'again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) await controller.delete(subject);
  }
}

/// Live progress for the one download allowed at a time.
class _DownloadStrip extends StatelessWidget {
  const _DownloadStrip({
    required this.subject,
    required this.fetched,
    this.total,
    this.fraction,
  });

  final String subject;
  final int fetched;

  /// How many the whole bank holds, when the server said so.
  final int? total;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // A whole bank can run to thousands of questions on a slow connection, so
    // the strip says how far along it is whenever it can — a count that only
    // goes up gives no sense of how much longer there is to wait.
    final label = total == null || total! <= 0
        ? 'Downloading $subject — $fetched questions so far'
        : 'Downloading $subject — $fetched of $total questions';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s3),
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(Tokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: fraction,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: Tokens.s4),
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: Tokens.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.rSm),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                backgroundColor: scheme.onPrimaryContainer.withValues(
                  alpha: 0.15,
                ),
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One subject row. Shared with the dashboard's "jump back in" shelf.
class SubjectCard extends StatelessWidget {
  const SubjectCard({
    super.key,
    required this.entry,
    required this.onStart,
    this.onDownload,
    this.onDelete,
    this.busy = false,
  });

  final SubjectEntry entry;
  final VoidCallback onStart;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  /// True while another subject is downloading — the download button is held
  /// back rather than queuing a second parallel fetch.
  final bool busy;

  /// A stable colour per subject, so Chemistry is the same shade every time
  /// without anyone maintaining a lookup table.
  static Color _accentFor(String subject, ColorScheme scheme) {
    const palette = [
      BlueprintPalette.b500,
      BlueprintPalette.success,
      BlueprintPalette.warning,
      BlueprintPalette.b700,
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF06B6D4),
    ];
    final hash = subject.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0xFFFF);
    return palette[hash % palette.length].withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.85 : 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentFor(entry.name, scheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onStart,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                ),
                alignment: Alignment.center,
                child: Text(
                  // Grapheme-aware, and tolerant of a blank subject name
                  // rather than throwing on `first`.
                  entry.name.characters.take(1).toString().toUpperCase(),
                  style: text.titleLarge?.copyWith(color: accent),
                ),
              ),
              const SizedBox(width: Tokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Tokens.s1),
                    Row(
                      children: [
                        Icon(
                          entry.isDownloaded
                              ? Icons.offline_pin_outlined
                              : Icons.cloud_outlined,
                          size: 14,
                          color: entry.isDownloaded
                              ? BlueprintPalette.success
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Tokens.s1),
                        Flexible(
                          child: Text(
                            entry.isDownloaded
                                ? '${entry.questionCount} questions offline'
                                  '${entry.isStale ? ' • update available' : ''}'
                                : 'Tap to practise, or download for offline',
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDownload != null)
                IconButton(
                  onPressed: busy ? null : onDownload,
                  tooltip: entry.isDownloaded
                      ? 'Refresh offline questions'
                      : 'Download for offline',
                  icon: Icon(
                    entry.isDownloaded
                        ? Icons.refresh
                        : Icons.download_for_offline_outlined,
                  ),
                ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'Remove from device',
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

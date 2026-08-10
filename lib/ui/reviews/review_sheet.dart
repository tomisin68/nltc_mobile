import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/platform_review_repository.dart';
import '../../data/services/prefs_service.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/star_rating.dart';

/// Asks for a review at a moment the student is already pleased.
///
/// The same document the Settings card writes, reached at a different time. A
/// student who has just seen a good score is being asked about something they
/// are still feeling; the same question inside Settings is being asked of
/// somebody who came to change their password.
///
/// [context] must outlive the sheet — pass the screen's context, not a builder's.
Future<void> showReviewSheet(BuildContext context, {String? prompt}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReviewSheet(prompt: prompt),
    );

class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key, this.prompt});

  /// The line above the stars — usually a reference to whatever just happened.
  final String? prompt;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  final _body = TextEditingController();
  int _rating = 0;
  bool _saving = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  /// Declining is recorded as settled, not as "ask again later".
  ///
  /// Somebody who closes this has answered the question. Asking a second time
  /// is how a prompt turns into the thing people uninstall an app over.
  Future<void> _decline() async {
    await context.read<PrefsService>().markReviewSettled();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _saving) return;
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;
    final prefs = context.read<PrefsService>();
    final repository = context.read<PlatformReviewRepository>();

    setState(() => _saving = true);
    try {
      await repository.save(
        uid: uid,
        profile: session.profile,
        rating: _rating,
        body: _body.text,
        isFirst: true,
      );
      await prefs.markReviewSettled();
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast('Thank you — your review is with our team.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast('Could not send that. Try again from Settings.',
          variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

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
                Icon(Icons.star_rounded,
                    color: BlueprintPalette.warning, size: 24),
                const SizedBox(width: Tokens.s2),
                const Expanded(
                  child: Text(
                    'How are we doing?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : _decline,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Not now',
                ),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            Text(
              widget.prompt == null
                  ? 'Tell other students what studying here has actually been '
                      'like. The honest version is more useful to them than the '
                      'polite one.'
                  : '${widget.prompt} Would you tell other students what '
                      'studying here has been like? The honest version is more '
                      'useful to them than the polite one.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s4),
            Center(
              child: StarRating(
                rating: _rating,
                size: 34,
                onRate: _saving ? null : (n) => setState(() => _rating = n),
              ),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _body,
              enabled: !_saving,
              maxLines: 4,
              maxLength: 1500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What should other students know? (optional)',
                alignLabelWithHint: true,
              ),
            ),
            Text(
              'If we publish it, your first name, last initial and profile '
              'picture appear with it. Your email, phone number and results '
              'never do. You can edit or delete it at any time in Settings.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _decline,
                    child: const Text('No thanks'),
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: FilledButton(
                    onPressed: _rating == 0 || _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send review'),
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

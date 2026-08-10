import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/session_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/toast.dart';
import '../../core/widgets/app_card.dart';

/// The student's review of NLTC itself.
///
/// One per student, and the document id IS their uid — which makes "one per
/// student" a property of the data rather than a rule somebody has to check.
/// Writes always land as `pending`: the collection is world-readable so the
/// marketing site can show published reviews, and an unmoderated
/// world-readable text field on a platform full of under-18s is a liability
/// rather than a feature. The Firestore rules enforce that, not just this
/// widget. Mirrors `PlatformReviewCard.jsx` on the web.
class PlatformReviewCard extends StatefulWidget {
  const PlatformReviewCard({super.key});

  @override
  State<PlatformReviewCard> createState() => _PlatformReviewCardState();
}

class _PlatformReviewCardState extends State<PlatformReviewCard> {
  static const _wordFor = ['Poor', 'Not great', 'Okay', 'Good', 'Excellent'];

  final _body = TextEditingController();
  int _rating = 0;
  String? _status;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>>? get _ref {
    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('platformReviews').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _ref?.get();
      if (!mounted) return;
      final data = snap?.data();
      setState(() {
        if (data != null) {
          _rating = (data['rating'] as num?)?.toInt() ?? 0;
          _body.text = (data['body'] as String?) ?? '';
          _status = (data['status'] as String?) ?? 'pending';
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_rating == 0 || _saving) return;
    final ref = _ref;
    if (ref == null) return;

    final session = context.read<SessionController>();
    final profile = session.profile;
    final name = [
      profile?.firstName,
      profile?.lastName,
    ].where((p) => p != null && p.trim().isNotEmpty).join(' ').trim();

    setState(() => _saving = true);
    try {
      await ref.set({
        'uid': session.account?.uid,
        'name': name.isEmpty ? 'Student' : name,
        'photo': profile?.profileImage,
        'targetExam': profile?.targetExam,
        'rating': _rating,
        'body': _body.text.trim(),
        // An edit re-enters moderation, so a review cannot be published clean
        // and then rewritten into something else.
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
        if (_status == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _status = 'pending';
        _editing = false;
        _saving = false;
      });
      showToast('Thank you — your review has been sent.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast('Could not save your review. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(Tokens.s5),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final hasReview = _status != null;
    final showForm = _editing || !hasReview;

    return AppCard(
      title: hasReview ? 'Your review of NLTC' : 'How are we doing?',
      titleIcon: Icons.star_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasReview)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s3),
              child: Text(
                'Tell other students what studying here has actually been like. '
                'The honest version is more useful to them than the polite one.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),

          _Stars(
            rating: _rating,
            interactive: showForm,
            onRate: (n) => setState(() => _rating = n),
          ),
          if (_rating > 0)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s1),
              child: Text(
                _wordFor[_rating - 1],
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),

          if (showForm) ...[
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
              'never do. You can edit or delete it at any time.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            Row(
              children: [
                if (hasReview) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _editing = false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _rating == 0 || _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(hasReview ? 'Update review' : 'Send review'),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (_body.text.trim().isNotEmpty) ...[
              const SizedBox(height: Tokens.s3),
              Text(
                '“${_body.text.trim()}”',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.65,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Tokens.s3),
            Text(
              switch (_status) {
                'published' => 'Your review is live. Edit it any time — an '
                    'edited review goes back for a quick read first.',
                'hidden' => 'We were not able to publish this one. You are '
                    'welcome to rewrite it, or email us if you think that was '
                    'a mistake.',
                _ => 'Thank you — your review is with our team. We publish '
                    'reviews once we have read them.',
              },
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            OutlinedButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_rounded, size: 17),
              label: const Text('Edit my review'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({
    required this.rating,
    required this.interactive,
    required this.onRate,
  });

  final int rating;
  final bool interactive;
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var n = 1; n <= 5; n++)
            IconButton(
              onPressed: interactive ? () => onRate(n) : null,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              iconSize: 28,
              tooltip: interactive ? '$n star${n > 1 ? 's' : ''}' : null,
              icon: Icon(
                n <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                color: n <= rating
                    ? BlueprintPalette.warning
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ],
      );
}

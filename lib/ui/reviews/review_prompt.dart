import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/platform_review_repository.dart';
import '../../data/services/prefs_service.dart';
import '../core/state/session_controller.dart';
import 'review_sheet.dart';

/// The score a sitting has to clear before the app treats it as a good moment.
///
/// Deliberately not "any finished test": asking somebody who just scored 31%
/// what they think of the platform gets an answer about the platform.
const _goodScore = 75.0;

/// The shortest sitting that counts. A four-question warm-up scored 100% is not
/// evidence of anything, and a student who has barely used NLTC has no review
/// to give yet.
const _minQuestions = 10;

/// Offers the review sheet if this result is worth celebrating and the student
/// has not already been asked, or already answered.
///
/// Silent in every case where the answer is no — callers fire this and forget
/// it, so a wrong moment costs nothing and needs no handling at the call site.
Future<void> maybeAskForReview(
  BuildContext context, {
  required double score,
  required int total,
  required String subject,
}) async {
  if (score < _goodScore || total < _minQuestions) return;

  final prefs = context.read<PrefsService>();
  if (!prefs.mayAskForReview) return;

  final uid = context.read<SessionController>().account?.uid;
  if (uid == null) return;

  // A student who already left one is settled by definition — record that so
  // the round trip only ever happens once, even across reinstalls of the app's
  // prefs. Reviewing from Settings does not go through this file.
  final existing = await context.read<PlatformReviewRepository>().mine(uid);
  if (existing != null) {
    await prefs.markReviewSettled();
    return;
  }

  await prefs.markReviewAsked();
  if (!context.mounted) return;

  await showReviewSheet(
    context,
    prompt: 'You just scored ${score.round()}% in $subject.',
  );
}

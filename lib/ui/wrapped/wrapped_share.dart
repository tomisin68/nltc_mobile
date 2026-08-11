import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Captures a [RepaintBoundary] and hands it to the system share sheet.
///
/// The card is captured from the one already on screen rather than built
/// off-screen: an off-screen tree has to be laid out and pumped by hand, and
/// getting that subtly wrong ships a card with missing fonts or a blank logo.
/// What the student saw is what gets shared.
class WrappedShare {
  const WrappedShare._();

  /// Rendered at 3× so the PNG holds up when a chat app scales it back up.
  static const _pixelRatio = 3.0;

  /// Shares the boundary behind [key] as a PNG, with [message] as the text.
  ///
  /// Returns false when the card could not be handed over — the caller shows a
  /// toast rather than leaving the button looking dead. Everything from the
  /// capture to the share sheet is inside the guard, because a throw escaping
  /// here leaves the button spinning forever with nothing on screen to say why.
  static Future<bool> shareCard({
    required GlobalKey boundaryKey,
    required String message,
    required String fileName,
  }) async {
    try {
      final bytes = await _capture(boundaryKey);
      if (bytes == null) return false;

      await SharePlus.instance.share(
        ShareParams(
          text: message,
          files: [await stageFile(bytes, fileName)],
          subject: 'My NLTC Wrapped',
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Writes [bytes] to a real file under the temp directory and wraps it for
  /// the share sheet.
  ///
  /// The PNG has to be on disk before it is handed over. share_plus returns an
  /// `XFile` untouched whenever its `path` is non-empty — it only spills bytes
  /// to a file of its own for an `XFile` that has no path at all. So an
  /// `XFile.fromData(bytes, path: …)` names a file nobody ever wrote, and the
  /// Android side throws copying that path into its FileProvider cache. That
  /// was the "Could not build your card" every student hit: the card captured
  /// fine and was then handed over as a path to nothing.
  ///
  /// The temp directory is the app's own cache dir, which is where share_plus
  /// stages files itself — it copies from there into `caches/share_plus`, and
  /// refuses any path already inside that folder.
  @visibleForTesting
  static Future<XFile> stageFile(Uint8List bytes, String fileName) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return XFile(file.path, mimeType: 'image/png');
  }

  static Future<Uint8List?> _capture(GlobalKey key) async {
    // A boundary throws on toImage until it has been painted, and the tap that
    // gets here flips the share button into a spinner first — so there is a
    // frame in flight. Waiting for it to land is the whole precaution.
    //
    // This used to be a `debugNeedsPaint` check, which is assert-guarded: in a
    // release build reading it throws, the catch below turned that into null,
    // and every student saw "Could not build your card" while it worked fine in
    // debug. Nothing here may touch a debug-only API again.
    await SchedulerBinding.instance.endOfFrame;

    final object = key.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;

    final image = await object.toImage(pixelRatio: _pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

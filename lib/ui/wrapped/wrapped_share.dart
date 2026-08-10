import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
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
  /// Returns false when the card could not be captured — the caller shows a
  /// toast rather than leaving the button looking dead. A failure here is
  /// almost always "the boundary has not been painted yet", which is worth
  /// telling the student to retry rather than swallowing.
  static Future<bool> shareCard({
    required GlobalKey boundaryKey,
    required String message,
    required String fileName,
  }) async {
    final bytes = await _capture(boundaryKey);
    if (bytes == null) return false;

    final directory = await getTemporaryDirectory();
    final file = XFile.fromData(
      bytes,
      name: fileName,
      mimeType: 'image/png',
      path: '${directory.path}/$fileName',
    );

    await SharePlus.instance.share(
      ShareParams(
        text: message,
        files: [file],
        subject: 'My NLTC Wrapped',
      ),
    );
    return true;
  }

  static Future<Uint8List?> _capture(GlobalKey key) async {
    try {
      final object = key.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;

      // A boundary that has never been painted throws on toImage. Waiting for
      // the end of the frame is enough in every case that matters, because the
      // card is on screen by the time this button can be tapped.
      if (object.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 32));
      }

      final image = await object.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}

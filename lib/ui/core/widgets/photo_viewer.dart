import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// One picture, full screen, pinch to zoom.
///
/// Shared by the chat's image attachments and by profile photos, so a picture
/// opens the same way wherever it is tapped. The bytes come from the same disk
/// cache the thumbnail used, which is why a photo already on screen opens
/// instantly instead of downloading a second time.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.url, this.title});

  final String url;

  /// Whose picture this is, shown in the bar. Null for a chat attachment, where
  /// the sender is already obvious from the message it was tapped in.
  final String? title;

  /// Pushes the viewer. A no-op for an empty URL, so callers can wire it up to
  /// an avatar that may only have initials.
  static Future<void> open(
    BuildContext context,
    String? url, {
    String? title,
  }) {
    if (url == null || url.isEmpty) return Future<void>.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewer(url: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: title == null
              ? null
              : Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          actions: [
            IconButton(
              onPressed: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open',
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              errorWidget: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'That picture could not be loaded.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      );
}

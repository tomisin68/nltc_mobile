import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/link_preview_service.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/in_app_browser.dart';

/// The card under a message that carries a link: the page's picture, its title
/// and the domain it lives on.
///
/// Nothing is drawn until the page has answered — a placeholder that may never
/// resolve into anything would make every message with a link in it jump. It
/// also stays hidden for a page with no Open Graph tags, because a card holding
/// only a domain says less than the link above it already does.
class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.isMine,
  });

  /// Already normalised — see `firstLinkIn`.
  final String url;

  /// Which bubble this is sitting in, which decides the tint it needs to stay
  /// legible on.
  final bool isMine;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreview? _preview;

  @override
  void initState() {
    super.initState();
    // A link already fetched paints on the first frame, so scrolling back
    // through a conversation doesn't make every card fade in again.
    _preview = context.read<LinkPreviewService>().cachedPreview(widget.url);
    if (_preview == null) _load();
  }

  @override
  void didUpdateWidget(LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled bubble can arrive holding a different message's link.
    if (oldWidget.url != widget.url) {
      _preview = context.read<LinkPreviewService>().cachedPreview(widget.url);
      if (_preview == null) _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    final preview = await context.read<LinkPreviewService>().preview(url);
    // The list may have scrolled this bubble away, or reused it for another
    // message, while the page was being read.
    if (!mounted || url != widget.url) return;
    setState(() => _preview = preview);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // On the navy bubble the card is a lighter panel of the same colour; on the
    // pale one it is a shade darker. Either way it reads as part of the message.
    final surface = widget.isMine
        ? scheme.onPrimary.withValues(alpha: 0.14)
        : scheme.surface;
    final foreground = widget.isMine ? scheme.onPrimary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openInAppBrowser(
            context,
            preview.url,
            title: preview.title,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: preview.imageUrl!,
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  fadeInDuration: Motion.fast,
                  // The card is worth showing for its title alone, so a picture
                  // that will not load simply isn't part of it.
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.siteName ?? preview.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: foreground.withValues(alpha: 0.65),
                      ),
                    ),
                    if (preview.title != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        preview.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ],
                    if (preview.description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        preview.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: foreground.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

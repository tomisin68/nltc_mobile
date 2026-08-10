import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_palette.dart';

/// Renders a study note written in the admin console's HTML editor.
///
/// The editor is a raw-HTML textarea, so a teacher writing a note reaches for
/// exactly what they would use on a worksheet: coloured headings, highlighted
/// key terms, a table of formulae, and diagrams pasted in either as a Storage
/// URL or as an inline `data:` URI. All of that has to survive the trip.
///
/// Three things the stock [HtmlWidget] does not do, which this adds:
///
///  * **Images fit the page.** `WidgetFactory.buildImageWidget` renders an
///    `<img>` with no width or height attributes at its intrinsic pixel size
///    with `BoxFit.fill`, so a 1600px-wide diagram overflowed the card and was
///    clipped. Every image here is bounded by the column width and keeps its
///    aspect ratio.
///  * **A failed image is visible.** The stock error builder collapses to an
///    empty widget, so a diagram that failed to load looked identical to a note
///    that never had one — the student had nothing to report and we had nothing
///    to debug. Broken images now say so.
///  * **Network images are cached.** The default `NetworkImage` re-downloads on
///    every rebuild and holds nothing between launches, which on a Nigerian
///    mobile connection is the difference between a note that opens and one
///    that doesn't.
///
/// Colour needs no special handling — the renderer honours `color` and
/// `background-color` — but it does need a surface worth honouring it against.
/// See [_paperSurface].
class NoteHtml extends StatelessWidget {
  const NoteHtml({super.key, required this.html});

  final String html;

  /// Tags dropped rather than rendered. The HTML comes from our own admin
  /// console, but it is still stored content flowing into the app, and none of
  /// these belong in a study note.
  static const _blocked = {
    'script',
    'iframe',
    'object',
    'embed',
    'form',
    'input',
    'button',
  };

  @override
  Widget build(BuildContext context) {
    return _PaperSurface(
      child: HtmlWidget(
        html,
        // Ink for paper, not for the app's surface — see [_PaperSurface].
        textStyle: const TextStyle(
          fontSize: 14.5,
          height: 1.7,
          color: BlueprintPalette.text1,
        ),
        factoryBuilder: _NoteWidgetFactory.new,
        customStylesBuilder: _stylesFor,
        customWidgetBuilder: (element) =>
            _blocked.contains(element.localName) ? const SizedBox.shrink() : null,
        onTapImage: (image) => _openViewer(context, image),
        onTapUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri == null) return false;
          return launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    );
  }

  /// Defaults for the elements a teacher actually types, matched to the
  /// website's `.study-note-content` rules in `src/styles/dashboard.css` so a
  /// note looks the same in both places. Anything the author styled inline
  /// wins over these — the point is to have something sensible underneath, not
  /// to overrule the person who wrote the note.
  static Map<String, String>? _stylesFor(dom.Element element) {
    switch (element.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
        return const {'margin': '20px 0 10px', 'line-height': '1.35'};
      case 'p':
        return const {'margin': '0 0 12px'};
      case 'ul':
      case 'ol':
        return const {'margin': '0 0 12px', 'padding-left': '22px'};
      case 'li':
        return const {'margin': '0 0 6px'};
      case 'blockquote':
        return const {
          'margin': '0 0 14px',
          'padding': '2px 0 2px 14px',
          'font-style': 'italic',
        };
      case 'table':
        return const {'margin': '0 0 14px'};
      case 'td':
      case 'th':
        return const {'padding': '6px 10px'};
      case 'code':
      case 'pre':
        return const {'font-family': 'monospace'};
      case 'hr':
        return const {'margin': '18px 0'};
      default:
        return null;
    }
  }

  void _openViewer(BuildContext context, ImageMetadata image) {
    final url = image.sources.isNotEmpty ? image.sources.first.url : null;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _NoteImageViewer(url: url, alt: image.alt ?? image.title),
      ),
    );
  }
}

/// Notes are authored against a white page.
///
/// A teacher who writes a navy heading and a pale-yellow highlight is picturing
/// paper, and those choices are unreadable on the app's dark navy surface — the
/// heading disappears into the background and the highlight blinds. Rather than
/// silently rewriting the author's colours, which is the one thing this reader
/// is meant not to do, the note is given the page it was written for: a light
/// sheet, in both themes. In dark mode it reads as a sheet of paper held under
/// a lamp, which is a familiar enough object to not look like a bug.
class _PaperSurface extends StatelessWidget {
  const _PaperSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: _paperSurface(context),
          borderRadius: BorderRadius.circular(Tokens.rSm),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? BlueprintPalette.b200.withValues(alpha: 0.25)
                : BlueprintPalette.b100,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s4),
          child: child,
        ),
      );
}

Color _paperSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF7FAFF) // very slightly warm, so it reads as paper
        : BlueprintPalette.white;

/// Overrides image building so every `<img>` in a note is bounded, cached and
/// visibly broken when it breaks.
class _NoteWidgetFactory extends WidgetFactory {
  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url;
    final alt = src.image?.alt ?? src.image?.title;

    final Widget image;
    if (url.startsWith('data:image/')) {
      image = _dataUriImage(url, alt);
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      image = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, _) => const _ImagePlaceholder(),
        errorWidget: (_, _, _) => _BrokenImage(alt: alt),
      );
    } else {
      // asset:, file: and anything else keeps the package's own handling —
      // a note has no business carrying those, but dropping them silently
      // would be worse than rendering them.
      return super.buildImageWidget(tree, src);
    }

    // A note is a single column, so an image never wants to be wider than the
    // column. Height is left to the aspect ratio; `BoxFit.contain` inside an
    // unbounded-height column would otherwise have nothing to work against.
    return Semantics(
      label: alt,
      image: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.rXs),
          child: SizedBox(width: double.infinity, child: image),
        ),
      ),
    );
  }

  Widget _dataUriImage(String url, String? alt) {
    final bytes = _decodeDataUri(url);
    if (bytes == null) return _BrokenImage(alt: alt);
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _BrokenImage(alt: alt),
    );
  }
}

/// Decodes an inline `data:image/…` diagram, base64 or percent-encoded.
///
/// Pasting a screenshot straight into the editor is the path of least
/// resistance for a teacher, so these are common — and so are truncated
/// pastes. A malformed payload throws inside the decoder, and an uncaught
/// exception here would take down the whole note rather than the one image.
Uint8List? _decodeDataUri(String url) {
  try {
    return UriData.parse(url).contentAsBytes();
  } catch (_) {
    return null;
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        height: 150,
        alignment: Alignment.center,
        color: BlueprintPalette.b50,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}

/// What a student sees when a diagram will not load.
///
/// Deliberately not silent: the stock renderer drops a failed image entirely,
/// which leaves a note reading "as shown in the diagram below" with nothing
/// below it and no way for anyone to tell whether the teacher forgot the image
/// or the network ate it.
class _BrokenImage extends StatelessWidget {
  const _BrokenImage({this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s4,
        ),
        decoration: BoxDecoration(
          color: BlueprintPalette.b50,
          borderRadius: BorderRadius.circular(Tokens.rXs),
          border: Border.all(color: BlueprintPalette.b100),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.image_not_supported_outlined,
              size: 18,
              color: BlueprintPalette.text3,
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Text(
                alt?.isNotEmpty == true
                    ? '$alt — image could not be loaded'
                    : 'This image could not be loaded.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: BlueprintPalette.text2,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Full-screen, pinch-zoomable view of a diagram.
///
/// Diagrams in science notes are the reason: a labelled circuit or a titration
/// curve shrunk to phone-column width is unreadable, and the student's only
/// other option is to give up on it.
class _NoteImageViewer extends StatelessWidget {
  const _NoteImageViewer({required this.url, this.alt});

  final String url;
  final String? alt;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: BlueprintPalette.ink,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: BlueprintPalette.white,
          elevation: 0,
          title: alt != null
              ? Text(alt!, style: const TextStyle(fontSize: 14))
              : null,
        ),
        body: Center(
          child: InteractiveViewer(maxScale: 5, child: _image()),
        ),
      );

  Widget _image() {
    if (url.startsWith('data:image/')) {
      final bytes = _decodeDataUri(url);
      if (bytes == null) return _BrokenImage(alt: alt);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _BrokenImage(alt: alt),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, _) => const CircularProgressIndicator(),
      errorWidget: (_, _, _) => _BrokenImage(alt: alt),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/in_app_browser.dart';

/// A study note that is a whole HTML document, drawn as one.
///
/// The notes that carry the teaching — a Biology topic with a labelled cell
/// diagram, a comparison table, colour-coded definition boxes — are authored as
/// complete HTML pages and uploaded as files. [NoteHtml] cannot show them and
/// never could: `flutter_widget_from_html_core` has no `<svg>` renderer, so
/// every diagram came out as a caption above nothing, and a `<style>` block is
/// not markup it reads at all, so the colours and boxes came out as plain text.
///
/// So a document note is not re-drawn — it is *rendered*, by the one thing on
/// the device that renders HTML. The page keeps its stylesheet and its diagrams
/// because nothing in between has an opinion about them. Same decision the web
/// makes with a sandboxed iframe; see `src/utils/noteDocument.js`.
///
/// **JavaScript is off.** A note is a page to read, and none of these documents
/// has ever needed a script — so the WebView is given none. That is a stronger
/// guarantee than sanitising: there is no engine for a script to run in, whatever
/// the stored HTML turns out to contain.
class NoteDocumentView extends StatefulWidget {
  const NoteDocumentView({super.key, required this.html});

  final String html;

  @override
  State<NoteDocumentView> createState() => _NoteDocumentViewState();
}

class _NoteDocumentViewState extends State<NoteDocumentView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      // Notes are authored against paper. Without this the WebView paints its
      // own default behind the page for the first frame, which in dark mode is
      // a black flash before a white note.
      ..setBackgroundColor(BlueprintPalette.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false || !mounted) return;
            setState(() => _loading = false);
          },
        ),
      )
      ..loadHtmlString(framedNoteDocument(widget.html));
  }

  @override
  void didUpdateWidget(NoteDocumentView old) {
    super.didUpdateWidget(old);
    if (old.html == widget.html) return;
    setState(() => _loading = true);
    _controller.loadHtmlString(framedNoteDocument(widget.html));
  }

  /// The note itself loads from a `data:`/`about:` URL, which is the only
  /// navigation that belongs inside this view. A tapped link is the student
  /// asking to leave the note, and leaves — into the in-app browser, so they
  /// come back to the note rather than to a cold start.
  NavigationDecision _onNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      // `data:` and `about:blank` are the document being loaded; anything else
      // non-web (a dialer, a mail app) goes to the system.
      if (uri.scheme == 'data' || uri.scheme == 'about' || uri.scheme.isEmpty) {
        return NavigationDecision.navigate;
      }
      handOffToSystem(request.url);
      return NavigationDecision.prevent;
    }
    openInAppBrowser(context, request.url);
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: BlueprintPalette.white,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// True when [html] has to be rendered as a document rather than as markup.
///
/// Kept identical to `isNoteDocument()` in the website's
/// `src/utils/noteDocument.js` — a note must not render one way here and
/// another way on the web. Change both together.
bool isNoteDocument(String? html) =>
    RegExp(r'<(?:!doctype\s+html|html|head|style|svg)\b', caseSensitive: false)
        .hasMatch(html ?? '');

/// [html] with the head a phone needs in front of it.
///
/// Everything here is a *default*: it is injected at the top of `<head>`, so the
/// note's own stylesheet comes after it and wins on anything it has an opinion
/// about. Only the viewport is non-negotiable — without it the WebView lays the
/// page out at 980px and scales it down, which turns a labelled diagram into a
/// smudge and is exactly the "cannot see it clearly" this view exists to fix.
///
/// Mirrors `FRAME_HEAD` in the website's `noteDocument.js`, minus its height
/// reporter: that is a script, this WebView has no JavaScript, and it does not
/// need one — the note scrolls itself.
String framedNoteDocument(String html) {
  const head = '<meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>'
      'html{-webkit-text-size-adjust:100%;}'
      'body{overflow-wrap:break-word;}'
      'img,svg{max-width:100%;height:auto;}'
      'pre{overflow-x:auto;}'
      '</style>';

  final headTag = RegExp('<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (headTag != null) {
    return html.replaceRange(headTag.end, headTag.end, head);
  }
  // A note stored as a bare `<style>…</style><h1>…` fragment — a document by
  // every rule that matters, without the wrapper. Give it one.
  return '<!doctype html><html><head>$head</head><body>$html</body></html>';
}

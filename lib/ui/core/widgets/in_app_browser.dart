import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_palette.dart';
import '../toast.dart';

/// Opens [url] in a browser screen inside the app.
///
/// Handing a link to the system browser drops the student out of NLTC entirely
/// — on Android they come back to a cold start, and mid-payment they come back
/// to nothing at all. Everything the app links to is web content it can host
/// itself, so it does.
///
/// Returns the URL the browser stopped on when [closeWhen] matched — that is how
/// the checkout learns the payment finished — or null when the student simply
/// backed out.
///
/// Schemes a WebView cannot render (`mailto:`, `tel:`, a bank's own app) are
/// still handed to the system: those are not web pages, and refusing them would
/// break the one flow that genuinely needs to leave.
Future<String?> openInAppBrowser(
  BuildContext context,
  String url, {
  String? title,
  bool Function(Uri url)? closeWhen,
}) {
  // A link typed as `www.example.com` has no scheme of its own; assume https
  // rather than rejecting it, the way an address bar does.
  url = normaliseUrl(url);
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    showToast('That link is not valid.', variant: ToastVariant.error);
    return Future<String?>.value();
  }
  // Nothing a WebView can draw — a phone number, an email, a bank app.
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return launchUrl(uri, mode: LaunchMode.externalApplication)
        .then<String?>((_) => null)
        .catchError((_) => null);
  }

  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => InAppBrowser(url: url, title: title, closeWhen: closeWhen),
    ),
  );
}

/// A minimal browser: the page, where it came from, and a way back.
class InAppBrowser extends StatefulWidget {
  const InAppBrowser({
    super.key,
    required this.url,
    this.title,
    this.closeWhen,
  });

  final String url;

  /// Shown until the page names itself.
  final String? title;

  /// Pops the browser as soon as navigation reaches a matching URL, handing that
  /// URL back to the caller.
  final bool Function(Uri url)? closeWhen;

  @override
  State<InAppBrowser> createState() => _InAppBrowserState();
}

class _InAppBrowserState extends State<InAppBrowser> {
  late final WebViewController _controller;

  String? _pageTitle;
  String _currentUrl = '';
  int _progress = 0;
  bool _loading = true;

  /// Guards against popping twice — `onNavigationRequest` and `onPageStarted`
  /// can both see the closing URL.
  bool _closed = false;

  /// True once the `www.` fallback below has been tried, so a site that is down
  /// on both names fails rather than looping.
  bool _triedWithoutWww = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _loading = true;
            });
            _maybeClose(url);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            final pageTitle = await _controller.getTitle();
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _loading = false;
              _pageTitle = (pageTitle ?? '').trim().isEmpty ? null : pageTitle;
            });
          },
          onWebResourceError: (error) {
            // Only the page itself failing is worth saying — a missing image or
            // a blocked tracker fires this too.
            if (error.isForMainFrame == false || !mounted) return;
            if (_retryWithoutWww(error)) return;
            setState(() => _loading = false);
            showToast(
              'That page could not load. Check your connection.',
              variant: ToastVariant.error,
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// Retries a dead `www.` host at the bare domain, once.
  ///
  /// `www.nltc.com.ng` has no DNS record of its own while `nltc.com.ng` serves
  /// the site, so a student sent the address with the `www.` on the front got
  /// nothing but an error — and that is how most people write a web address
  /// down. A missing `www` record is a common way to publish a domain and not
  /// something a student can be expected to work around, so the browser does.
  ///
  /// Only a name that failed to resolve is retried: a site that is genuinely
  /// down, or refusing the connection, must still say so.
  bool _retryWithoutWww(WebResourceError error) {
    if (_triedWithoutWww) return false;
    if (error.errorType != WebResourceErrorType.hostLookup) return false;

    final uri = Uri.tryParse(_currentUrl);
    final host = uri?.host ?? '';
    if (uri == null || !host.toLowerCase().startsWith('www.')) return false;

    _triedWithoutWww = true;
    final fallback = uri.replace(host: host.substring(4));
    setState(() => _currentUrl = fallback.toString());
    _controller.loadRequest(fallback);
    return true;
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      // A bank app, a wallet, a dialer. The WebView would only show an error.
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
        showToast('No app can open that link.', variant: ToastVariant.error);
        return false;
      });
      return NavigationDecision.prevent;
    }

    if (_maybeClose(request.url)) return NavigationDecision.prevent;
    return NavigationDecision.navigate;
  }

  /// True when this URL is the one the caller was waiting for.
  bool _maybeClose(String url) {
    final matcher = widget.closeWhen;
    if (matcher == null || _closed) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !matcher(uri)) return false;

    _closed = true;
    // Popping from inside a navigation callback runs during the WebView's own
    // frame; deferring keeps the route teardown out of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(url);
    });
    return true;
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(_currentUrl)?.host ?? '';

    return PopScope(
      // The hardware back button walks the page history first, the way a
      // browser does, and only leaves once there is nothing behind it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pageTitle ?? widget.title ?? 'Loading…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              if (host.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 10, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => _controller.reload(),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload',
            ),
            IconButton(
              onPressed: () => launchUrl(
                Uri.parse(_currentUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open in browser',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: SizedBox(
              height: 2,
              child: _loading
                  ? LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress / 100,
                      minHeight: 2,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        body: SafeArea(child: WebViewWidget(controller: _controller)),
      ),
    );
  }
}

/// What counts as a link in a message. Same pattern as the web's `URL_REGEX`.
///
/// Top-level so the preview card and the tappable text agree exactly: a card
/// under a link the text did not underline would be baffling.
final RegExp kUrlPattern = RegExp(
  r'''https?:\/\/[^\s<>"']+|www\.[^\s<>"']+''',
  caseSensitive: false,
);

/// Turns what somebody typed into something that can actually be opened.
///
/// `www.nltc.com.ng` has no scheme, so `Uri.parse` reads it as a *path* — a
/// relative reference nothing can launch. Assuming `https` is what every browser
/// address bar does with the same input.
String normaliseUrl(String raw) {
  final trimmed = raw.trim();
  return RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(trimmed)
      ? trimmed
      : 'https://$trimmed';
}

/// The first link in [text], ready to open, or null if there isn't one.
String? firstLinkIn(String text) {
  final match = kUrlPattern.firstMatch(text);
  return match == null ? null : normaliseUrl(match.group(0)!);
}

/// Text with its URLs turned into tappable links that open inside the app.
///
/// Shared by both chats — the class chat and the private one — so a link looks
/// and behaves the same wherever a student meets it.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor,
  });

  final String text;
  final TextStyle style;

  /// Defaults to a colour that reads as a link against [style]'s own colour.
  final Color? linkColor;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizerHolder>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final holder in _recognizers) {
      holder.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final matches = kUrlPattern.allMatches(widget.text).toList();
    if (matches.isEmpty) return Text(widget.text, style: widget.style);

    _disposeRecognizers();

    // Bright enough to stand out against both bubble colours, and underlined as
    // well — colour alone is not a signal every student can see.
    final linkColor = widget.linkColor ?? _defaultLinkColor(context);

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final raw = match.group(0)!;
      final href = normaliseUrl(raw);
      final holder = TapGestureRecognizerHolder(
        () => openInAppBrowser(context, href),
      );
      _recognizers.add(holder);
      spans.add(
        TextSpan(
          text: raw,
          style: TextStyle(
            color: linkColor,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: linkColor.withValues(alpha: 0.6),
          ),
          recognizer: holder.recognizer,
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(TextSpan(children: spans), style: widget.style);
  }

  /// A link on a navy bubble and a link on a pale one need different blues to
  /// stay legible; the text colour behind them is what says which one this is.
  Color _defaultLinkColor(BuildContext context) {
    final base = widget.style.color ?? Theme.of(context).colorScheme.onSurface;
    final onDark = ThemeData.estimateBrightnessForColor(base) == Brightness.light;
    return onDark ? BlueprintPalette.b200 : BlueprintPalette.b600;
  }
}

/// Keeps a [TapGestureRecognizer] alive for the life of a span.
///
/// A recognizer attached to a `TextSpan` must outlive the build that created it
/// and be disposed by hand — Flutter asserts loudly if either is got wrong.
class TapGestureRecognizerHolder {
  TapGestureRecognizerHolder(VoidCallback onTap)
      : recognizer = TapGestureRecognizer()..onTap = onTap;

  final TapGestureRecognizer recognizer;

  void dispose() => recognizer.dispose();
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../domain/referral.dart';
import '../state/session_controller.dart';
import '../theme/app_palette.dart';
import 'empty_state.dart';
import 'in_app_browser.dart';

/// A web page that lives *inside* a dashboard view, rather than on a route of
/// its own.
///
/// [InAppBrowser] is the full-screen version, with its own app bar and a close
/// button; this is the same thing without the chrome, for a destination the
/// shell already titles and frames. It keeps the browser's navigation rules —
/// web links stay inside, anything else is handed to the system — and takes the
/// hardware back button while there is page history to walk, so back means
/// "back a page" here the way it does in a browser.
class EmbeddedWebView extends StatefulWidget {
  const EmbeddedWebView({
    super.key,
    required this.url,
    this.enableShare = false,
  });

  final String url;

  /// Shows a share bar under the progress line, carrying whatever page is
  /// currently open rather than the URL this view started on.
  ///
  /// Off by default. A student passing an article to a WhatsApp group is the
  /// cheapest distribution NLTC has, but it only makes sense on a page that is
  /// meant to be public — nobody should be invited to share a billing page.
  final bool enableShare;

  @override
  State<EmbeddedWebView> createState() => _EmbeddedWebViewState();
}

class _EmbeddedWebViewState extends State<EmbeddedWebView> {
  late final WebViewController _controller;

  int _progress = 0;
  bool _loading = true;
  bool _canGoBack = false;

  /// The page actually on screen, which is not [widget.url] once the student
  /// has tapped through to an article. Sharing the wrong one of those is the
  /// difference between sending a friend an article and sending them an index.
  late String _currentUrl = widget.url;
  String? _currentTitle;

  /// Set when the page itself failed to load. Kept separate from [_loading] so
  /// a retry can clear it without flashing the error behind the new page.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => handOffToSystem(request.url)
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _currentUrl = url;
                // Dropped the moment navigation starts: keeping the old page's
                // title around would label the new page with the last one's
                // headline for as long as it takes to load.
                _currentTitle = null;
              });
            }
          },
          onPageFinished: (url) async {
            final canGoBack = await _controller.canGoBack();
            final title = await _controller.getTitle();
            if (!mounted) return;
            setState(() {
              _loading = false;
              _canGoBack = canGoBack;
              _currentUrl = url;
              _currentTitle = title;
            });
          },
          onWebResourceError: (error) {
            // Only the page itself failing is worth an error state — a missing
            // image or a blocked tracker fires this too.
            if (error.isForMainFrame == false || !mounted) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _reload() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  /// Hands the page on screen to the system share sheet.
  ///
  /// The uid rides along so a signup that follows the link is traceable to the
  /// student who shared it — see [withReferral], which leaves the canonical URL
  /// alone and refuses to tag anything that is not ours.
  Future<void> _share() async {
    final uid = context.read<SessionController>().account?.uid;
    final link = withReferral(_currentUrl, uid);
    final title = _cleanTitle;

    await SharePlus.instance.share(
      ShareParams(
        text: title == null ? link : '$title\n\n$link',
        subject: title,
      ),
    );
  }

  /// The page title with the site's own suffix trimmed off — "… | NLTC Online"
  /// reads as noise once the link underneath already says nltc.com.ng.
  String? get _cleanTitle {
    final raw = _currentTitle?.trim();
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.split(RegExp(r'\s*\|\s*')).first.trim();
    return trimmed.isEmpty ? raw : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Only claim the back button while there is somewhere to go back to;
      // otherwise back leaves the app, exactly as it does on every other view.
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Claiming the back button also takes it from the drawer, which closes
        // itself through the route's local history rather than through a
        // PopScope — so back over an open drawer has to be handed back, or it
        // would walk a page nobody can currently see.
        final scaffold = Scaffold.maybeOf(context);
        if (scaffold != null && scaffold.isDrawerOpen) {
          scaffold.closeDrawer();
          return;
        }
        if (await _controller.canGoBack()) await _controller.goBack();
      },
      child: Column(
        children: [
          SizedBox(
            height: 2,
            child: _loading
                ? LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2,
                  )
                : null,
          ),
          if (widget.enableShare && !_failed)
            _ShareBar(
              label: _cleanTitle == null
                  ? 'Share this page'
                  : 'Share “${_cleanTitle!}”',
              onShare: _share,
            ),
          Expanded(
            child: _failed
                ? _OfflineState(url: widget.url, onRetry: _reload)
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

/// A slim, always-present invitation to pass the page on.
///
/// Deliberately a bar rather than a floating button: the shell already owns the
/// bottom-right corner for support, and a share affordance that has to be
/// hunted for is a share that does not happen.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.label, required this.onShare});

  final String label;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onShare,
        child: Container(
          constraints: const BoxConstraints(minHeight: Tokens.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s4,
            vertical: Tokens.s2,
          ),
          child: Row(
            children: [
              Icon(Icons.ios_share_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              Text(
                'WhatsApp, X, anywhere',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  const _OfflineState({required this.url, required this.onRetry});

  final String url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: Tokens.s10),
      children: [
        EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'This page needs a connection',
          message: 'It could not be loaded. Check your data and try again.',
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open in browser'),
          ),
        ),
      ],
    );
  }
}

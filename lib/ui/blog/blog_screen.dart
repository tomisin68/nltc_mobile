import 'package:flutter/material.dart';

import '../core/widgets/embedded_web_view.dart';

/// Where the blog lives. The posts are written, edited and laid out on the
/// website — there is no second copy of them to keep in step here.
const kBlogUrl = 'https://nltc.com.ng/blog';

/// The article a notification points at, or null if it doesn't point at one.
///
/// The backend attaches `data.url` to every push, but most of those are website
/// routes (`/student.html?view=chat`) that mean nothing to the app and would
/// only drop the student on a login page. Only blog links are followed, and only
/// on the site the blog is actually published on.
String? blogUrlForRoute(String? route) {
  final raw = (route ?? '').trim();
  if (raw.isEmpty) return null;

  // A bare path is what the backend sends; a full URL is what a hand-written
  // notification tends to carry.
  if (raw.startsWith('/blog/') || raw == '/blog') {
    return 'https://nltc.com.ng$raw';
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return null;
  final host = uri.host.toLowerCase();
  final onSite = host == 'nltc.com.ng' || host == 'www.nltc.com.ng';
  if (!onSite || !uri.path.startsWith('/blog')) return null;
  return uri.toString();
}

/// The Blog destination.
///
/// A WebView rather than a native list on purpose: posts are HTML written in the
/// admin editor — headings, images, tables, embedded links — and re-implementing
/// that rendering in Flutter would mean every new thing an author can write is a
/// thing the app can get wrong. Showing the real page keeps the app and the site
/// telling students the same story, and the in-app browser means reading one
/// never drops them out of NLTC.
/// Sharing is on here and nowhere else in the app: the blog is the one surface
/// NLTC actually wants forwarded. A post that reaches a WhatsApp group reaches
/// thirty students who have never heard of us, which no amount of meta-tag
/// work on the site can do by itself.
class BlogScreen extends StatelessWidget {
  const BlogScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const EmbeddedWebView(url: kBlogUrl, enableShare: true);
}

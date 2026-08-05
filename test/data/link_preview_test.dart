import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/services/link_preview_service.dart';
import 'package:nltc/ui/core/widgets/in_app_browser.dart';

/// The two pure halves of a chat link preview: working out what the link is,
/// and working out what the page at the end of it says about itself.
void main() {
  group('normaliseUrl', () {
    test('assumes https for an address typed without a scheme', () {
      // The bug this exists for: `Uri.parse('www.nltc.com.ng')` is a relative
      // path, not a host, so nothing could open it.
      expect(normaliseUrl('www.nltc.com.ng'), 'https://www.nltc.com.ng');
      expect(normaliseUrl('nltc.com.ng/blog'), 'https://nltc.com.ng/blog');
    });

    test('leaves an address that already names its scheme alone', () {
      expect(normaliseUrl('http://nltc.com.ng'), 'http://nltc.com.ng');
      expect(normaliseUrl('https://nltc.com.ng'), 'https://nltc.com.ng');
      expect(normaliseUrl('mailto:hello@nltc.com.ng'),
          'mailto:hello@nltc.com.ng');
    });

    test('ignores surrounding whitespace', () {
      expect(normaliseUrl('  www.nltc.com.ng '), 'https://www.nltc.com.ng');
    });
  });

  group('firstLinkIn', () {
    test('finds a bare www address in a sentence', () {
      expect(
        firstLinkIn('check www.nltc.com.ng for the timetable'),
        'https://www.nltc.com.ng',
      );
    });

    test('takes only the first link', () {
      expect(
        firstLinkIn('https://a.example and https://b.example'),
        'https://a.example',
      );
    });

    test('is null for a message with no link in it', () {
      expect(firstLinkIn('see you at 4pm'), isNull);
      // A bare domain with no `www.` is not treated as a link, matching the
      // web's regex — otherwise "e.g" and "i.e" would become links.
      expect(firstLinkIn('meet at 4 p.m'), isNull);
    });
  });

  group('LinkPreviewService.parseHtml', () {
    final page = Uri.parse('https://nltc.com.ng/blog/jamb-tips');

    test('reads the Open Graph tags', () {
      final preview = LinkPreviewService.parseHtml('''
        <html><head>
          <meta property="og:title" content="Ten JAMB tips">
          <meta property="og:description" content="How to prepare">
          <meta property="og:image" content="https://cdn.example/x.png">
          <meta property="og:site_name" content="NLTC">
        </head></html>
      ''', page);

      expect(preview, isNotNull);
      expect(preview!.title, 'Ten JAMB tips');
      expect(preview.description, 'How to prepare');
      expect(preview.imageUrl, 'https://cdn.example/x.png');
      expect(preview.siteName, 'NLTC');
    });

    test('accepts the attributes in either order', () {
      final preview = LinkPreviewService.parseHtml(
        '<meta content="Backwards" property="og:title">',
        page,
      );
      expect(preview?.title, 'Backwards');
    });

    test('keeps an apostrophe inside a double-quoted title', () {
      // The live landing page's own og:title. A pattern that stopped at either
      // quote mark cut this to "NLTC Online | Nigeria".
      final preview = LinkPreviewService.parseHtml(
        '<meta property="og:title" '
        'content="NLTC Online | Nigeria\'s #1 JAMB, WAEC &amp; NECO Prep" />',
        page,
      );
      expect(
        preview?.title,
        "NLTC Online | Nigeria's #1 JAMB, WAEC & NECO Prep",
      );
    });

    test('keeps a > inside a quoted description', () {
      final preview = LinkPreviewService.parseHtml(
        '<meta property="og:title" content="Marks">'
        '<meta property="og:description" content="Scores > 70% pass">',
        page,
      );
      expect(preview?.description, 'Scores > 70% pass');
    });

    test('decodes numeric entities', () {
      final preview = LinkPreviewService.parseHtml(
        '<meta property="og:title" content="Nigeria&#8217;s &#x23; 1 &amp; only">',
        page,
      );
      expect(preview?.title, 'Nigeria’s # 1 & only');
    });

    test('falls back to twitter tags, then to <title>', () {
      expect(
        LinkPreviewService
            .parseHtml('<meta name="twitter:title" content="Tweeted">', page)
            ?.title,
        'Tweeted',
      );
      expect(
        LinkPreviewService.parseHtml('<title>Plain old title</title>', page)
            ?.title,
        'Plain old title',
      );
    });

    test('resolves a relative og:image against the page', () {
      final preview = LinkPreviewService.parseHtml('''
        <meta property="og:title" content="Ten JAMB tips">
        <meta property="og:image" content="/img/cover.png">
      ''', page);
      expect(preview?.imageUrl, 'https://nltc.com.ng/img/cover.png');
    });

    test('unescapes entities and collapses whitespace in a title', () {
      final preview = LinkPreviewService.parseHtml(
        '<title>JAMB\n   &amp; WAEC   prep</title>',
        page,
      );
      expect(preview?.title, 'JAMB & WAEC prep');
    });

    test('is null for a page with nothing to show', () {
      // A card carrying only a domain says less than the underlined link above
      // it already does, so none is drawn.
      expect(LinkPreviewService.parseHtml('<html><body>hi</body></html>', page),
          isNull);
      expect(LinkPreviewService.parseHtml('<title>   </title>', page), isNull);
    });

    test('host drops the www so the card names the site, not the subdomain', () {
      final preview = LinkPreviewService.parseHtml(
        '<meta property="og:title" content="X">',
        Uri.parse('https://www.nltc.com.ng/a'),
      );
      expect(preview?.host, 'nltc.com.ng');
    });

    test('survives a page truncated mid-tag', () {
      // The fetch stops at 96 KB, so the last tag is very often cut in half.
      final preview = LinkPreviewService.parseHtml(
        '<meta property="og:title" content="Ten JAMB tips">'
        '<meta property="og:desc',
        page,
      );
      expect(preview?.title, 'Ten JAMB tips');
      expect(preview?.description, isNull);
    });
  });

  group('LinkPreview round-trips through the disk cache', () {
    test('keeps every field it was given', () {
      const original = LinkPreview(
        url: 'https://nltc.com.ng',
        title: 'NLTC',
        description: 'Exam prep',
        imageUrl: 'https://cdn.example/x.png',
        siteName: 'NLTC Online',
      );
      final restored = LinkPreview.fromJson(original.toJson());
      expect(restored?.url, original.url);
      expect(restored?.title, original.title);
      expect(restored?.description, original.description);
      expect(restored?.imageUrl, original.imageUrl);
      expect(restored?.siteName, original.siteName);
    });

    test('rejects a corrupt entry rather than half-restoring it', () {
      expect(LinkPreview.fromJson(null), isNull);
      expect(LinkPreview.fromJson({'title': 'no url'}), isNull);
    });
  });
}

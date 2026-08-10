import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/domain/referral.dart';

void main() {
  group('inviteLink', () {
    test('tags the signup URL with the sharer', () {
      expect(inviteLink('abc123'),
          'https://nltc.com.ng/auth?mode=signup&ref=abc123');
    });

    test('falls back to a plain signup link with no uid', () {
      expect(inviteLink(null), kSignupUrl);
      expect(inviteLink(''), kSignupUrl);
      expect(inviteLink('   '), kSignupUrl);
    });
  });

  group('withReferral', () {
    test('adds ref to an NLTC URL', () {
      final tagged = withReferral('https://nltc.com.ng/blog/how-to-pass', 'u1');
      expect(Uri.parse(tagged).queryParameters['ref'], 'u1');
      expect(Uri.parse(tagged).path, '/blog/how-to-pass');
    });

    test('keeps existing query parameters', () {
      final tagged =
          withReferral('https://nltc.com.ng/blog?page=2', 'u1');
      final query = Uri.parse(tagged).queryParameters;
      expect(query['page'], '2');
      expect(query['ref'], 'u1');
    });

    test('replaces a ref already on the URL rather than doubling it', () {
      final tagged =
          withReferral('https://nltc.com.ng/blog?ref=someone-else', 'u1');
      expect(Uri.parse(tagged).queryParameters['ref'], 'u1');
      expect('ref='.allMatches(tagged).length, 1);
    });

    test('accepts the www host', () {
      final tagged = withReferral('https://www.nltc.com.ng/blog', 'u1');
      expect(Uri.parse(tagged).queryParameters['ref'], 'u1');
    });

    test('refuses to tag a URL that is not ours', () {
      const foreign = 'https://example.com/article';
      expect(withReferral(foreign, 'u1'), foreign);
    });

    test('leaves the URL alone with no uid', () {
      const url = 'https://nltc.com.ng/blog/how-to-pass';
      expect(withReferral(url, null), url);
      expect(withReferral(url, ''), url);
    });

    test('leaves unparseable input untouched', () {
      expect(withReferral('not a url', 'u1'), 'not a url');
      expect(withReferral('/blog/relative', 'u1'), '/blog/relative');
    });
  });

  group('inviteMessage', () {
    test('leads with the student, and carries the link', () {
      final message = inviteMessage(
        title: 'The Regular',
        monthLabel: 'July 2026',
        uid: 'u1',
      );

      expect(message, contains('July 2026'));
      expect(message, contains('The Regular'));
      expect(message, contains('ref=u1'));
    });
  });
}

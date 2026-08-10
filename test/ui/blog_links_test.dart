import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/ui/blog/blog_screen.dart';

/// What a tapped notification is allowed to open.
///
/// The backend attaches `data.url` to every push it sends, and most of those
/// are website routes the app has no business following — so this decides, and
/// it decides conservatively.
void main() {
  group('blogUrlForRoute', () {
    test('follows the path the backend sends for a published post', () {
      // `POST /api/notifications/blog-published` sends exactly this shape.
      expect(
        blogUrlForRoute('/blog/how-to-pass-jamb-2026'),
        'https://nltc.com.ng/blog/how-to-pass-jamb-2026',
      );
      expect(blogUrlForRoute('/blog'), 'https://nltc.com.ng/blog');
    });

    test('follows a full blog URL, with or without the www', () {
      expect(
        blogUrlForRoute('https://nltc.com.ng/blog/waec-syllabus'),
        'https://nltc.com.ng/blog/waec-syllabus',
      );
      expect(
        blogUrlForRoute('https://www.nltc.com.ng/blog/waec-syllabus'),
        'https://www.nltc.com.ng/blog/waec-syllabus',
      );
    });

    test('refuses a dashboard route', () {
      // These are the routes chat and payment notifications carry. Opening one
      // would drop the student on the website's login page.
      expect(blogUrlForRoute('/student.html?view=chat&chatId=abc'), isNull);
      expect(blogUrlForRoute('/dashboard'), isNull);
    });

    test('refuses a blog path on somebody else\'s domain', () {
      // A notification is only as trustworthy as what wrote it; a link the app
      // opens without asking must at least be on the site the blog is on.
      expect(blogUrlForRoute('https://evil.example/blog/free-jamb'), isNull);
      expect(blogUrlForRoute('https://nltc.com.ng.evil.example/blog'), isNull);
    });

    test('refuses a scheme a browser has no business opening', () {
      expect(blogUrlForRoute('javascript:alert(1)'), isNull);
      expect(blogUrlForRoute('file:///etc/passwd'), isNull);
    });

    test('has nothing to open when the notification carries no route', () {
      expect(blogUrlForRoute(null), isNull);
      expect(blogUrlForRoute(''), isNull);
      expect(blogUrlForRoute('   '), isNull);
    });
  });
}

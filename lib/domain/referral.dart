/// Where an invite sends somebody.
const kSignupUrl = 'https://nltc.com.ng/auth?mode=signup';

/// What a referrer earns when somebody signs up through their link.
///
/// Display only. `REFERRAL_XP` in the backend's `services/referralService.js` is
/// what actually pays out, and it pays the referrer's own document directly —
/// the app has no way to award itself XP, and shouldn't. Keep the two in step:
/// this is the number a student is promised on the invite card.
const kReferralXp = 200;

/// The student's personal invite link.
///
/// The uid rides along as `ref` so signups can be traced back to whoever's card
/// was shared. `AuthPage.jsx` on the website reads it, stashes it across the
/// signup flow and writes `referredBy` onto the new user document — the app
/// only has to produce the link.
///
/// A Firebase uid is not a secret (it is already visible wherever a student
/// appears in public data) and it grants nothing on its own, so it is safe to
/// put in a link that gets forwarded around WhatsApp.
String inviteLink(String? uid) {
  final id = (uid ?? '').trim();
  return id.isEmpty ? kSignupUrl : '$kSignupUrl&ref=$id';
}

/// Tags any NLTC page with the sharer's uid.
///
/// Used when a student passes a blog post on. The post's own `<link
/// rel="canonical">` still points at the clean URL, so search engines keep
/// treating the tagged and untagged links as one page — the parameter only
/// tells us who sent the reader.
///
/// Returns [url] untouched when there is no uid, or when the URL is not ours:
/// a uid has no business being appended to somebody else's domain.
String withReferral(String url, String? uid) {
  final id = (uid ?? '').trim();
  if (id.isEmpty) return url;

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  final host = uri.host.toLowerCase();
  if (host != 'nltc.com.ng' && host != 'www.nltc.com.ng') return url;

  return uri.replace(
    queryParameters: {...uri.queryParameters, 'ref': id},
  ).toString();
}

/// The message for a bare invite, with no Wrapped card behind it.
///
/// Says what the student gets rather than what NLTC is, because this one is
/// forwarded cold — there is no screenshot alongside it doing the explaining.
String shareInviteMessage(String? uid) =>
    'I am prepping for JAMB, WAEC and NECO on NLTC — past questions, mock '
    'exams and live classes, all in one place. Join me: ${inviteLink(uid)}';

/// The message that travels with a shared Wrapped card.
///
/// Deliberately about the student rather than about NLTC: a card that says
/// "look what I did" gets forwarded, and an advert does not.
String inviteMessage({required String title, required String monthLabel, String? uid}) =>
    'My NLTC Wrapped for $monthLabel — apparently I am "$title". '
    'Come and study with me: ${inviteLink(uid)}';

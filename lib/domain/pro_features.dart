/// The three things a free account does not include.
///
/// Every other part of the platform is open for the whole free trial and locks
/// only when the account lapses — that gate is [AccessState.active]. These three
/// are different: they are never part of a free account, trial or not, so they
/// gate on [AccessState.isPro] instead. A student who has just signed up can
/// still practise, watch lessons and read notes; they cannot chat, join a live
/// class, or open a Wrapped until they pay.
///
/// The copy lives here rather than in each screen so the sidebar chip, the
/// panel that replaces a gated view and the sheet raised by a blocked tap all
/// describe the same feature the same way.
library;

enum ProFeature {
  messages(
    label: 'Messages',
    note: 'Messages is a Pro feature.',
    body: 'Direct messages, study groups and your class group chat are part of '
        'Pro. Upgrade to message classmates and tutors, and to be added to '
        'group chats.',
    perks: [
      'Message any student or tutor on NLTC',
      'Join study groups and class group chats',
      'Share photos, notes and voice notes',
    ],
  ),
  liveClasses(
    label: 'Live Classes',
    note: 'Live classes are a Pro feature.',
    body: 'Live classes are taught by NLTC tutors on camera, with polls and '
        'questions as you go. Upgrade to join a class — you can still see '
        "what's coming up.",
    perks: [
      'Join every live class on the timetable',
      'Ask questions and answer polls in the room',
      'Earn XP for every session you attend',
    ],
  ),
  wrapped(
    label: 'My Wrapped',
    note: 'My Wrapped is a Pro feature.',
    body: 'Your Wrapped is the story of your month — every test, your best '
        'subject and your streak, in a card you can share. Upgrade to unlock '
        "this month's.",
    perks: [
      'A recap of your month, every month',
      'Your best subject, streak and XP, told as a story',
      'A share card for your class group or status',
    ],
  );

  const ProFeature({
    required this.label,
    required this.note,
    required this.body,
    required this.perks,
  });

  /// What the student calls it — matches the sidebar link exactly.
  final String label;

  /// One line, for a toast or the heading of a gate. Kept short enough to read
  /// at a glance in a snackbar.
  final String note;

  /// The paragraph on the upsell panel: what the feature is, then what upgrading
  /// gets them. Says what they are missing rather than only that they are
  /// blocked.
  final String body;

  /// Three selling points, bulleted under [body].
  final List<String> perks;
}

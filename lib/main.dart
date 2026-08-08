import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repositories/attempt_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/billing_repository.dart';
import 'data/repositories/broadcast_repository.dart';
import 'data/repositories/chat_repository.dart';
import 'data/repositories/exam_result_repository.dart';
import 'data/repositories/gamification_repository.dart';
import 'data/repositories/learning_profile_repository.dart';
import 'data/repositories/live_repository.dart';
import 'data/repositories/mock_exam_repository.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/presence_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/question_report_repository.dart';
import 'data/repositories/question_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'data/repositories/study_note_repository.dart';
import 'data/repositories/subject_repository.dart';
import 'data/repositories/support_repository.dart';
import 'data/repositories/video_repository.dart';
import 'data/services/api_client.dart';
import 'data/services/firestore_cache.dart';
import 'data/services/link_preview_service.dart';
import 'data/services/local_database.dart';
import 'data/services/mission_signals.dart';
import 'data/services/prefs_service.dart';
import 'data/services/push_service.dart';
import 'firebase_options.dart';
import 'ui/auth/auth_gate.dart';
import 'ui/core/state/activity_controller.dart';
import 'ui/core/state/notification_controller.dart';
import 'ui/core/state/practice_controller.dart';
import 'ui/core/state/presence_controller.dart';
import 'ui/core/state/session_controller.dart';
import 'ui/core/state/dashboard_badge_controller.dart';
import 'ui/core/state/dashboard_controller.dart';
import 'ui/core/state/theme_controller.dart';
import 'ui/core/state/xp_service.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/toast.dart';

Future<void> main() async {
  // Must run before any plugin work — Firebase.initializeApp talks to the
  // platform channels, which aren't up until the binding is.
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // All opened here rather than lazily so the first frame can read the saved
    // theme and the cached profile synchronously — no spinner, and no flash of
    // the wrong brightness.
    //
    // One SharedPreferences instance is shared by the three things that need
    // key/value storage; opening it once keeps them from racing each other on a
    // cold start.
    final sharedPrefs = await SharedPreferences.getInstance();
    final localDatabase = await LocalDatabase.open();

    runApp(
      NltcApp(
        prefs: PrefsService(sharedPrefs),
        sharedPrefs: sharedPrefs,
        localDatabase: localDatabase,
      ),
    );
  } catch (error) {
    // Without this the app dies on a black screen and the student has nothing
    // to report but "it won't open".
    runApp(_StartupFailureApp(error: error));
  }
}

/// Owns the object graph. Everything below reaches for its dependencies
/// through `context.read`, so screens never construct a repository themselves.
class NltcApp extends StatelessWidget {
  const NltcApp({
    super.key,
    required this.prefs,
    required this.sharedPrefs,
    required this.localDatabase,
  });

  final PrefsService prefs;

  /// The raw store, for the two collaborators that keep their own keyspace:
  /// the Firestore read cache and the daily mission signals.
  final SharedPreferences sharedPrefs;

  final LocalDatabase localDatabase;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PrefsService>.value(value: prefs),
        Provider<LocalDatabase>.value(value: localDatabase),
        Provider<FirestoreCache>(create: (_) => FirestoreCache(sharedPrefs)),
        // App-wide, so the same link pasted into three conversations is read
        // once and every bubble showing it shares the answer.
        Provider<LinkPreviewService>(
          create: (_) => LinkPreviewService(sharedPrefs),
        ),
        Provider<MissionSignals>(create: (_) => MissionSignals(sharedPrefs)),
        Provider<ApiClient>(create: (_) => ApiClient()),
        Provider<PushService>(create: (_) => PushService()),
        Provider<AuthRepository>(
          create: (context) => AuthRepository(prefs: context.read()),
        ),
        Provider<QuestionRepository>(
          create: (context) => QuestionRepository(local: context.read()),
        ),
        // One instance for the whole app on purpose: it remembers which
        // questions have already been reported, so the hall and the corrections
        // screen agree about what the student has already told us.
        Provider<QuestionReportRepository>(
          create: (_) => QuestionReportRepository(),
        ),
        Provider<ProfileRepository>(create: (_) => ProfileRepository()),
        Provider<PresenceRepository>(create: (_) => PresenceRepository()),
        Provider<LearningProfileRepository>(
          create: (context) => LearningProfileRepository(
            api: context.read(),
            cache: context.read(),
          ),
        ),
        Provider<LiveRepository>(
          create: (context) => LiveRepository(api: context.read()),
        ),
        Provider<ChatRepository>(
          create: (context) => ChatRepository(api: context.read()),
        ),
        Provider<BillingRepository>(
          create: (context) => BillingRepository(
            api: context.read(),
            cache: context.read(),
          ),
        ),
        Provider<ScheduleRepository>(
          create: (context) => ScheduleRepository(api: context.read()),
        ),
        Provider<SubjectRepository>(
          create: (context) => SubjectRepository(cache: context.read()),
        ),
        Provider<GamificationRepository>(
          create: (context) => GamificationRepository(api: context.read()),
        ),
        Provider<BroadcastRepository>(
          create: (context) => BroadcastRepository(api: context.read()),
        ),
        Provider<VideoRepository>(
          create: (context) => VideoRepository(cache: context.read()),
        ),
        Provider<MockExamRepository>(create: (_) => MockExamRepository()),
        Provider<SupportRepository>(create: (_) => SupportRepository()),
        Provider<ExamResultRepository>(
          create: (context) => ExamResultRepository(cache: context.read()),
        ),
        Provider<StudyNoteRepository>(
          create: (context) => StudyNoteRepository(cache: context.read()),
        ),
        Provider<AttemptRepository>(
          create: (context) => AttemptRepository(
            api: context.read(),
            local: context.read(),
          ),
        ),
        Provider<NotificationRepository>(
          create: (context) => NotificationRepository(
            api: context.read(),
            local: context.read(),
          ),
        ),
        ChangeNotifierProvider<ThemeController>(
          create: (context) => ThemeController(context.read()),
        ),
        ChangeNotifierProvider<DashboardController>(
          create: (_) => DashboardController(),
        ),
        ChangeNotifierProvider<SessionController>(
          create: (context) => SessionController(
            auth: context.read(),
            local: context.read(),
            cache: context.read(),
          ),
        ),
        // Not a ChangeNotifier — it reports through toasts and by patching the
        // session, so nothing watches it directly.
        Provider<XpService>(
          create: (context) => XpService(
            gamification: context.read(),
            session: context.read(),
          ),
        ),
        ChangeNotifierProvider<PracticeController>(
          create: (context) => PracticeController(context.read()),
        ),
        ChangeNotifierProvider<ActivityController>(
          create: (context) => ActivityController(context.read())..reload(),
        ),
        // The sidebar's live dot and chat badge follow the signed-in student the
        // same way, and stop listening the moment they sign out.
        ChangeNotifierProxyProvider<SessionController, DashboardBadgeController>(
          create: (context) =>
              DashboardBadgeController(chats: context.read<ChatRepository>()),
          update: (context, session, controller) =>
              controller!..bindTo(session.account?.uid),
        ),
        // Presence follows the account too: signing in marks this student here,
        // signing out marks them away, and everything the chat screens watch
        // hangs off the same object so one person is only ever listened to once.
        ChangeNotifierProxyProvider<SessionController, PresenceController>(
          create: (context) => PresenceController(presence: context.read()),
          update: (context, session, controller) =>
              controller!..bindTo(session.account?.uid),
        ),
        // Proxied on the session so the inbox follows the signed-in student:
        // it loads and registers for push on sign-in, and empties on sign-out.
        ChangeNotifierProxyProvider<SessionController, NotificationController>(
          create: (context) => NotificationController(
            repository: context.read(),
            push: context.read(),
          ),
          update: (context, session, controller) =>
              controller!..bindTo(session.account?.uid),
        ),
      ],
      child: const _NltcMaterialApp(),
    );
  }
}

class _NltcMaterialApp extends StatelessWidget {
  const _NltcMaterialApp();

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<ThemeController, ThemeMode>((c) => c.mode);

    return MaterialApp(
      // Lets repositories and controllers raise toasts without a BuildContext,
      // the way the web's module-level showToast does.
      scaffoldMessengerKey: toastMessengerKey,
      title: 'NLTC Online',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}

/// Last-resort screen for a failed startup — a bad `google-services.json`, or
/// a device that won't give us a writable database directory.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 56),
                    const SizedBox(height: 24),
                    Text(
                      'NLTC could not start',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Close the app and open it again. If this keeps '
                      'happening, send us this message:\n\n$error',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

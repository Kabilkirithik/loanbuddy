import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/inspection_home_screen.dart';
import 'services/submission_service.dart';

/// Populated once at startup. The capture screen needs the camera list
/// synchronously when it opens, and enumerating cameras is slow enough to be
/// visible if done on tap.
List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only. Progress photos are compared frame to frame across weeks,
  // so a consistent orientation is part of the verification, not a preference.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    cameras = await availableCameras();
  } on CameraException {
    cameras = const [];
  }

  final submissions = SubmissionService(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8090',
    ),
    authToken: const String.fromEnvironment('AUTH_TOKEN', defaultValue: 'dev'),
  );

  // Anything stranded from a previous session goes out first on native.
  if (!kIsWeb) {
    unawaited(submissions.flushQueue());
  }

  runApp(SiteCheckApp(submissions: submissions));
}

void unawaited(Future<void> f) {}

/// Field conditions drive every choice here: direct sunlight, one-handed use,
/// dusty screens, ₹8,000 Android phones. High contrast, large targets, and a
/// single saturated accent reserved for the one action that matters.
class Palette {
  static const ink = Color(0xFF14202B);
  static const inkMuted = Color(0xFF5A6B7A);
  static const concrete = Color(0xFFEEF1F4);
  static const line = Color(0xFFD5DCE3);
  static const surface = Color(0xFFFFFFFF);

  /// Reserved for the capture action and the burned-in stamp rule. It appears
  /// nowhere else, so its presence always means the same thing.
  static const signal = Color(0xFFE8B828);

  static const verified = Color(0xFF1B7F5A);
  static const blocked = Color(0xFFC0392B);
}

class SiteCheckApp extends StatelessWidget {
  const SiteCheckApp({super.key, required this.submissions});

  final SubmissionService submissions;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);

    return MaterialApp(
      title: 'SiteCheck',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: Palette.concrete,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.ink,
          primary: Palette.ink,
          surface: Palette.surface,
          error: Palette.blocked,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Palette.ink,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        textTheme: base.textTheme
            .apply(bodyColor: Palette.ink, displayColor: Palette.ink)
            .copyWith(
              headlineSmall: const TextStyle(
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Palette.ink,
              ),
              titleMedium: const TextStyle(
                fontSize: 17,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Palette.ink,
              ),
              bodyMedium: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Palette.ink,
              ),
              bodySmall: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Palette.inkMuted,
              ),
            ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: Palette.ink,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Palette.ink,
          contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      home: InspectionHomeScreen(submissions: submissions),
    );
  }
}
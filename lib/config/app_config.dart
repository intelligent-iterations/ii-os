import 'package:firebase_core/firebase_core.dart';

abstract final class AppConfig {
  static const String buildNumber = String.fromEnvironment(
    'II_OS_BUILD_NUMBER',
    defaultValue: 'local',
  );

  static const String buildGitSha = String.fromEnvironment(
    'II_OS_BUILD_GIT_SHA',
    defaultValue: 'local',
  );

  static String buildLabel({String? number}) {
    final value = number ?? buildNumber;
    return value == 'local' ? 'Build local' : 'Build #$value';
  }

  static String buildDetails({String? number, String? gitSha}) {
    final label = buildLabel(number: number);
    final sha = gitSha ?? buildGitSha;
    if (sha == 'local' || sha.isEmpty) return label;
    final shortSha = sha.length <= 7 ? sha : sha.substring(0, 7);
    return '$label · commit $shortSha';
  }

  static const bool useEmulators = bool.fromEnvironment(
    'II_OS_USE_EMULATORS',
    defaultValue: false,
  );

  static const bool localDevelopmentAuthBootstrap = bool.fromEnvironment(
    'II_OS_LOCAL_DEVELOPMENT_AUTH_BOOTSTRAP',
    defaultValue: false,
  );

  static const String localDevelopmentAuthEmail = String.fromEnvironment(
    'II_OS_LOCAL_DEVELOPMENT_AUTH_EMAIL',
  );

  static const String localEmulatorAuthEmail = String.fromEnvironment(
    'II_OS_LOCAL_EMULATOR_AUTH_EMAIL',
  );

  static const String controlApiBaseUrl = String.fromEnvironment(
    'II_OS_CONTROL_API_BASE_URL',
    defaultValue: '/api',
  );

  /// Repository that owns operator-triggered mobile release workflows.
  ///
  /// An empty value disables mobile update dispatch. Deployments opt in with
  /// their implementation repository instead of inheriting a maintainer
  /// repository from this package.
  static const String mobileUpdateRepository = String.fromEnvironment(
    'II_OS_MOBILE_UPDATE_REPOSITORY',
  );

  static const String googleIosClientId = String.fromEnvironment(
    'II_OS_GOOGLE_IOS_CLIENT_ID',
  );

  static const String googleAndroidServerClientId = String.fromEnvironment(
    'II_OS_GOOGLE_ANDROID_SERVER_CLIENT_ID',
  );

  static const String firebaseWebVapidKey = String.fromEnvironment(
    'II_OS_FIREBASE_WEB_VAPID_KEY',
  );

  static const FirebaseOptions firebaseOptions = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'II_OS_FIREBASE_API_KEY',
      defaultValue: 'ii-os-local-api-key',
    ),
    appId: String.fromEnvironment(
      'II_OS_FIREBASE_APP_ID',
      defaultValue: '1:100000000000:web:ii-os-local',
    ),
    messagingSenderId: String.fromEnvironment(
      'II_OS_FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '100000000000',
    ),
    projectId: String.fromEnvironment(
      'II_OS_FIREBASE_PROJECT_ID',
      defaultValue: 'demo-ii-os',
    ),
    authDomain: String.fromEnvironment(
      'II_OS_FIREBASE_AUTH_DOMAIN',
      defaultValue: 'demo-ii-os.firebaseapp.com',
    ),
  );
}

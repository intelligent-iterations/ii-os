import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'config/app_config.dart';
import 'navigation/app_route_state.dart';
import 'navigation/app_router.dart';
import 'providers/firebase/local_development_auth.dart';
import 'state/appearance_controller.dart';
import 'screens/auth_screen.dart';
import 'screens/operator_shell.dart';
import 'services/api_client.dart';
import 'services/client_breadcrumbs.dart';
import 'services/client_error_reporter.dart';
import 'services/startup_handoff.dart';
import 'widgets/auth_state_gate.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'widgets/unexpected_error_view.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: AppConfig.firebaseOptions);
}

void main() {
  var firstFrameRendered = false;
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      ErrorWidget.builder = buildIiOsErrorWidget;
      usePathUrlStrategy();
      await Firebase.initializeApp(options: AppConfig.firebaseOptions);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      if (AppConfig.useEmulators) {
        await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
        await LocalEmulatorAuthBootstrap.firebase(
          auth: FirebaseAuth.instance,
          enabled: AppConfig.localEmulatorAuthEmail.isNotEmpty,
          email: AppConfig.localEmulatorAuthEmail,
        ).run();
      } else {
        final localAuth = LocalDevelopmentAuthBootstrap.firebase(
          auth: FirebaseAuth.instance,
          enabled: AppConfig.localDevelopmentAuthBootstrap,
          baseUri: Uri.base,
          expectedEmail: AppConfig.localDevelopmentAuthEmail,
        );
        try {
          await localAuth.run();
        } finally {
          localAuth.close();
        }
      }

      final breadcrumbs = ClientBreadcrumbs();
      ClientBreadcrumbs.install(breadcrumbs);
      final reporter = ClientErrorReporter(breadcrumbs: breadcrumbs);
      ClientErrorReporter.install(reporter);
      ApiClient.failureObserver = (error, stackTrace, route) => reporter.report(
        error,
        stackTrace,
        source: 'api.request',
        route: route,
      );
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(
          reporter.report(
            details.exception,
            details.stack ?? StackTrace.current,
            source: 'flutter.framework',
          ),
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        unawaited(
          reporter.report(error, stackTrace, source: 'flutter.platform'),
        );
        return true;
      };
      runApp(const IiOsApp());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        firstFrameRendered = true;
        notifyIiOsFirstFrame();
      });
    },
    (error, stackTrace) {
      if (!firstFrameRendered) notifyIiOsStartupFailure();
      debugPrint('Uncaught ii-os error captured');
      unawaited(
        ClientErrorReporter.reportGlobal(
          error,
          stackTrace,
          source: 'flutter.zone',
        ),
      );
    },
  );
}

class IiOsApp extends StatefulWidget {
  const IiOsApp({super.key});

  @override
  State<IiOsApp> createState() => _IiOsAppState();
}

class _IiOsAppState extends State<IiOsApp> {
  late final GoRouter _router = createAppRouter(
    builder: (context, route) => _AuthGate(route: route),
    onNavigation: (route) => ClientBreadcrumbs.recordGlobal(
      category: 'navigation',
      name: 'route',
      route: route,
    ),
  );
  final AppearanceController _appearance = AppearanceController();

  @override
  void initState() {
    super.initState();
    unawaited(_appearance.load());
  }

  @override
  void dispose() {
    _appearance.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppearanceScope(
      notifier: _appearance,
      child: AnimatedBuilder(
        animation: _appearance,
        builder: (context, _) => MaterialApp.router(
          title: 'ii-os',
          debugShowCheckedModeBanner: false,
          theme: IiOsTheme.light(),
          darkTheme: IiOsTheme.dark(),
          themeMode: _appearance.mode,
          routerConfig: _router,
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.route});

  final AppRouteState route;

  @override
  Widget build(BuildContext context) {
    return AuthStateGate<User>(
      createStream: FirebaseAuth.instance.authStateChanges,
      waiting: const IiOsStartupView(),
      signedOut: const AuthScreen(),
      signedInBuilder: (context, user) =>
          OperatorShell(user: user, route: route),
    );
  }
}

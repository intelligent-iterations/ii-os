import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:stacked/stacked.dart';

import '../services/api_client.dart';
import '../services/apple_auth_service.dart';
import '../services/google_auth_service.dart';
import '../services/passwordless_auth_client.dart';

/// One federated sign-in attempt. Injected so a test can drive the screen
/// without a real provider SDK.
typedef ProviderSignIn = Future<UserCredential> Function();

/// State for the sign-in page.
///
/// Everything the old `_AuthScreenState` held except the text controllers,
/// which belong to the widgets that own them. That includes the resend
/// countdown timer, which is why rule 1 (`docs/ii-os-frontend.md` § Rules)
/// wanted it out of the screen: a page holding a `Timer` is a page nobody can
/// test without pumping a widget tree.
final class AuthViewModel extends BaseViewModel {
  /// Callers pass `auth:`, `google:`, `apple:`, and `clock:` -- a private named
  /// parameter keeps the field private without a redundant initializer.
  AuthViewModel({
    required this._auth,
    ProviderSignIn? google,
    ProviderSignIn? apple,
    DateTime Function()? clock,
  }) : _google = google ?? GoogleAuthService.signIn,
       _apple = apple ?? AppleAuthService.signIn,
       _now = clock ?? DateTime.now;

  final PasswordlessAuthClient _auth;
  final ProviderSignIn _google;
  final ProviderSignIn _apple;
  final DateTime Function() _now;

  Timer? _timer;

  PasswordlessChallenge? challenge;
  int remainingAttempts = 3;
  String? errorMessage;

  bool get enteringCode => challenge != null;

  bool get canResend {
    final current = challenge;
    return current != null && !_now().isBefore(current.resendAt);
  }

  Future<void> signInWithGoogle() => _runProvider(_google);

  Future<void> signInWithApple() => _runProvider(_apple);

  Future<void> _runProvider(ProviderSignIn action) async {
    _begin();
    try {
      await action();
    } on GoogleSignInException catch (error) {
      // A cancelled provider sheet is the user changing their mind, not a
      // failure worth reporting back to them.
      if (error.code != GoogleSignInExceptionCode.canceled) {
        errorMessage = error.description ?? 'Google Sign-In failed.';
      }
    } on FirebaseAuthException catch (error) {
      errorMessage = error.message ?? 'Authentication failed.';
    } on Object {
      errorMessage = 'Authentication failed. Please try again.';
    } finally {
      _end();
    }
  }

  /// Requests a code. [email] is ignored once a challenge exists, so the resend
  /// action cannot retarget a different address.
  Future<void> sendCode(String email) async {
    if (isBusy) return;
    final target = challenge?.email ?? email.trim();
    if (target.isEmpty) {
      errorMessage = 'Enter your email address.';
      notifyListeners();
      return;
    }
    await _run(() async {
      final started = await _auth.start(target);
      remainingAttempts = started.maxAttempts;
      challenge = started;
      _startResendCountdown();
    });
  }

  Future<void> verifyCode(String code) async {
    if (isBusy) return;
    if (code.length != 6) {
      errorMessage = 'Enter the 6-digit code.';
      notifyListeners();
      return;
    }
    await _run(() => _auth.verifyAndSignIn(code));
  }

  void useDifferentEmail() {
    _timer?.cancel();
    _auth.clear();
    challenge = null;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    _begin();
    try {
      await action();
    } on ApiFailure catch (error) {
      _absorbAttemptCount(error);
      errorMessage = error.message;
    } on FirebaseAuthException {
      errorMessage = 'The secure session could not be started.';
    } on Object {
      errorMessage = 'Sign-in failed. Please try again.';
    } finally {
      _end();
    }
  }

  /// The API reports how many tries are left. When it reaches zero the resend
  /// becomes available immediately, because waiting out the cooldown on a dead
  /// challenge helps nobody.
  void _absorbAttemptCount(ApiFailure error) {
    final details = error.details;
    if (details is! Map || details['remainingAttempts'] is! int) return;
    remainingAttempts = details['remainingAttempts'] as int;
    final current = challenge;
    if (remainingAttempts != 0 || current == null) return;
    challenge = PasswordlessChallenge(
      email: current.email,
      expiresAt: current.expiresAt,
      resendAt: _now(),
      maxAttempts: current.maxAttempts,
    );
  }

  void _begin() {
    errorMessage = null;
    setBusy(true);
  }

  void _end() => setBusy(false);

  /// Ticks once a second only until the resend unlocks, then stops. A timer
  /// that keeps firing after the button is enabled is a rebuild per second for
  /// nothing.
  void _startResendCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      if (canResend) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

import 'package:ii_os_functions/src/provider_contracts/identity_provider.dart';
import 'package:ii_os_functions/src/providers/firebase/firebase_identity_provider.dart';
import 'package:test/test.dart';

void main() {
  test('maps Firebase session details onto provider-neutral methods', () {
    expect(
      firebaseAuthenticationMethod(
        customClaims: const {'ii_os_auth_method': 'email_otp'},
        signInProvider: 'custom',
      ),
      AuthenticationMethod.emailOtp,
    );
    expect(
      firebaseAuthenticationMethod(
        customClaims: const {},
        signInProvider: 'google.com',
      ),
      AuthenticationMethod.google,
    );
    expect(
      firebaseAuthenticationMethod(
        customClaims: const {},
        signInProvider: 'apple.com',
      ),
      AuthenticationMethod.apple,
    );
  });

  test(
    'rejects unsupported production methods and isolates emulator trust',
    () {
      for (final provider in const ['password', 'github.com', 'custom']) {
        expect(
          firebaseAuthenticationMethod(
            customClaims: const {},
            signInProvider: provider,
          ),
          AuthenticationMethod.unsupported,
        );
      }
      expect(
        firebaseAuthenticationMethod(
          customClaims: const {},
          signInProvider: 'password',
          usingAuthEmulator: true,
        ),
        AuthenticationMethod.localDevelopment,
      );
    },
  );

  test(
    'accepts local development claims only when the profile enables them',
    () {
      expect(
        firebaseAuthenticationMethod(
          customClaims: const {'ii_os_auth_method': 'local_development'},
          signInProvider: 'custom',
        ),
        AuthenticationMethod.unsupported,
      );
      expect(
        firebaseAuthenticationMethod(
          customClaims: const {'ii_os_auth_method': 'local_development'},
          signInProvider: 'custom',
          allowLocalDevelopment: true,
        ),
        AuthenticationMethod.localDevelopment,
      );
    },
  );
}

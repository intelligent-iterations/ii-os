import 'package:ii_os_functions/src/auth_service.dart';
import 'package:ii_os_functions/src/provider_contracts/identity_provider.dart';
import 'package:test/test.dart';

void main() {
  test('accepts the provider-neutral supported methods', () {
    for (final method in const [
      AuthenticationMethod.emailOtp,
      AuthenticationMethod.google,
      AuthenticationMethod.apple,
      AuthenticationMethod.localDevelopment,
    ]) {
      expect(isSupportedAuthenticationMethod(method), isTrue);
    }
  });

  test('rejects an unsupported provider method', () {
    expect(
      isSupportedAuthenticationMethod(AuthenticationMethod.unsupported),
      isFalse,
    );
  });
}

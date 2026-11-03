import 'package:ii_os_functions/src/providers/firebase/local_development_token_issuer.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes an explicit dev operator identity and closed claim', () {
    final request = LocalDevelopmentTokenRequest.parse(
      projectId: 'example-project',
      profile: 'dev',
      email: ' Operator.Local@Example.com ',
      displayName: ' Codex local operator ',
      provision: true,
    );

    expect(request.projectId, 'example-project');
    expect(request.email, 'operator.local@example.com');
    expect(request.displayName, 'Codex local operator');
    expect(request.provision, isTrue);
    expect(request.developerClaims, {'ii_os_auth_method': 'local_development'});
  });

  test('refuses production, malformed projects, and malformed email', () {
    for (final values in [
      ('production-project', 'prod', 'operator@example.com'),
      ('not a project', 'dev', 'operator@example.com'),
      ('development-project', 'dev', 'not-an-email'),
    ]) {
      expect(
        () => LocalDevelopmentTokenRequest.parse(
          projectId: values.$1,
          profile: values.$2,
          email: values.$3,
          displayName: 'Local operator',
          provision: false,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });
}

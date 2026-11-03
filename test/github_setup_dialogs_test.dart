import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/screens/github_setup_dialogs.dart';

void main() {
  test('GitHub installation input accepts an ID or installation URL', () {
    expect(parseGitHubInstallationId('12345678'), 12345678);
    expect(
      parseGitHubInstallationId(
        'https://github.com/organizations/acme-co/settings/installations/12345678',
      ),
      12345678,
    );
    expect(parseGitHubInstallationId('https://example.com/12345678'), isNull);
    expect(parseGitHubInstallationId('-1'), isNull);
  });
}

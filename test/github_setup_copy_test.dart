import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/github_setup_copy.dart';
import 'package:ii_os/models/github_setup_readiness.dart';

void main() {
  test('every setup check has explicit product copy', () {
    for (final id in {
      ...repositoryConnectionCheckIds,
      ...permissionSetupCheckIds,
    }) {
      final check = _check(id);
      expect(setupTaskTitle(check), isNot('Check the connection again'));
      expect(
        setupTaskExplanation(check),
        isNot(startsWith('ii-os could not confirm')),
      );
    }
  });

  test('the direct check explicitly says no runner starts', () {
    final explanation = setupTaskExplanation(
      _check('github_repository_access'),
    );

    expect(explanation, contains('Firebase function'));
    expect(explanation, contains('short-lived GitHub installation token'));
    expect(explanation, contains('No workflow or runner starts'));
  });

  test('repository permissions and reviewed-commit bootstrap are in setup', () {
    expect(permissionSetupCheckIds, {
      'github_app_actions',
      'github_app_contents',
      'github_app_deployments',
      'github_app_pull_requests',
      'permission_bootstrap_tag',
    });
    expect(setupStepTitleFor(_check('github_app_actions')), 'Permissions');
    expect(setupStepTitleFor(_check('github_repository_access')), 'Repository');
  });
}

GitHubSetupCheckModel _check(String id) => GitHubSetupCheckModel(
  id: id,
  label: id,
  status: 'action_required',
  detail: '',
  guidance: '',
  repository: 'acme-co/example-app',
  action: '',
  currentValue: '',
  requiredValue: '',
);

import 'package:ii_os_functions/src/agent_repository_topology.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  test('same-repository publication works without implementation topology', () {
    final policy = AgentRepositoryTopology.fromConfiguration(
      coordinatorRepository: '',
      publicationTargets: '',
    );

    expect(
      policy.allowsPublication(
        source: 'acme-co/example-app',
        target: 'acme-co/example-app',
      ),
      isTrue,
    );
    expect(policy.allowsCoordinatorWorkflow('acme-co/coordinator'), isFalse);
    expect(
      policy.allowsPublication(
        source: 'acme-co/coordinator',
        target: 'acme-co/public-project',
      ),
      isFalse,
    );
  });

  test('deployment may allow exact coordinator publication targets', () {
    final policy = AgentRepositoryTopology.fromConfiguration(
      coordinatorRepository: 'acme-co/coordinator',
      publicationTargets: ' acme-co/public-project,acme-co/docs ',
    );

    expect(policy.allowsCoordinatorWorkflow('acme-co/coordinator'), isTrue);
    expect(
      policy.allowsPublication(
        source: 'acme-co/coordinator',
        target: 'acme-co/public-project',
      ),
      isTrue,
    );
    expect(
      policy.allowsPublication(
        source: 'acme-co/other',
        target: 'acme-co/public-project',
      ),
      isFalse,
    );
  });

  test('invalid implementation repository names fail closed', () {
    expect(
      () => AgentRepositoryTopology.fromConfiguration(
        coordinatorRepository: 'local-path',
        publicationTargets: '',
      ),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => AgentRepositoryTopology.fromConfiguration(
        coordinatorRepository: '',
        publicationTargets: 'https://github.com/acme-co/example-app',
      ),
      throwsA(isA<ApiError>()),
    );
  });
}

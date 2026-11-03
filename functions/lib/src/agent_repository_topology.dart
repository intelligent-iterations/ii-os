import 'api_error.dart';

/// Deployment-owned repository topology for agent workflow trust decisions.
///
/// The reusable source does not assume an organization, coordinator, or public
/// mirror. Deployments opt into cross-repository trust explicitly; all other
/// publication remains confined to the repository that started the workflow.
final class AgentRepositoryTopology {
  AgentRepositoryTopology({
    required String coordinatorRepository,
    required Iterable<String> publicationTargets,
  }) : coordinatorRepository = _optionalRepository(
         coordinatorRepository,
         'II_OS_AGENT_COORDINATOR_REPOSITORY',
       ),
       publicationTargets = Set.unmodifiable(
         publicationTargets.map(
           (repository) => _requiredRepository(
             repository,
             'II_OS_AGENT_PUBLICATION_TARGETS',
           ),
         ),
       );

  factory AgentRepositoryTopology.fromConfiguration({
    required String coordinatorRepository,
    required String publicationTargets,
  }) => AgentRepositoryTopology(
    coordinatorRepository: coordinatorRepository,
    publicationTargets: publicationTargets
        .split(',')
        .map((repository) => repository.trim())
        .where((repository) => repository.isNotEmpty),
  );

  final String coordinatorRepository;
  final Set<String> publicationTargets;

  bool allowsCoordinatorWorkflow(String repository) =>
      coordinatorRepository.isNotEmpty && repository == coordinatorRepository;

  bool allowsPublication({required String source, required String target}) =>
      source == target ||
      (allowsCoordinatorWorkflow(source) &&
          publicationTargets.contains(target));
}

String _optionalRepository(String value, String setting) {
  final repository = value.trim();
  if (repository.isEmpty) return '';
  return _requiredRepository(repository, setting);
}

String _requiredRepository(String value, String setting) {
  final repository = value.trim();
  if (!_repository.hasMatch(repository)) {
    throw ApiError(
      500,
      'agent_repository_policy_invalid',
      '$setting must contain GitHub owner/repository names.',
    );
  }
  return repository;
}

final _repository = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

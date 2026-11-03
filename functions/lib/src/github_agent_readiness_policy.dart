part of 'github_client.dart';

Map<String, Object?> agentWorkflowEnvironmentCheck(
  String source, {
  String? workTicketSource,
  required String repository,
}) {
  var bound = false;
  try {
    final root = _yamlObject(loadYaml(source));
    final jobs = root is Map<String, Object?> ? root['jobs'] : null;
    var gatewayBound = true;
    Object? dispatch = jobs is Map<String, Object?> ? jobs['dispatch'] : null;
    if (root is Map<String, Object?> &&
        dispatch is! Map<String, Object?> &&
        jobs is Map<String, Object?> &&
        workTicketSource != null) {
      gatewayBound = _agentWorkTicketGatewayBound(root, jobs);
      final workTicketRoot = _yamlObject(loadYaml(workTicketSource));
      final workTicketJobs = workTicketRoot is Map<String, Object?>
          ? workTicketRoot['jobs']
          : null;
      dispatch = workTicketJobs is Map<String, Object?>
          ? workTicketJobs['dispatch']
          : null;
    }
    final permissions = dispatch is Map<String, Object?>
        ? dispatch['permissions']
        : null;
    final steps = dispatch is Map<String, Object?> ? dispatch['steps'] : null;
    if (dispatch is Map<String, Object?> &&
        permissions is Map<String, Object?> &&
        steps is List<Object?>) {
      final normalizedSteps = steps.whereType<Map<String, Object?>>().toList();
      final apiToken = normalizedSteps
          .where((step) => step['id'] == 'api-token')
          .firstOrNull;
      final apiWith = apiToken?['with'];
      final cleanupIndex = normalizedSteps.indexWhere(
        (step) => step['name'] == 'Remove staged token files',
      );
      final finalizeIndex = normalizedSteps.indexWhere(
        (step) =>
            step['name'] ==
            'Finalize the exact ticket through the ii-os broker',
      );
      final authorizationIndex = normalizedSteps.indexWhere(
        (step) =>
            step['name'] == 'Authorize exact branch publication after cleanup',
      );
      final postReadIndex = normalizedSteps.indexWhere(
        (step) => step['id'] == 'post-read-token',
      );
      final publicationIndex = normalizedSteps.indexWhere(
        (step) => step['id'] == 'publication',
      );
      final fleetIndex = normalizedSteps.indexWhere(
        (step) => step['id'] == 'fleet',
      );
      final runtimeIndex = normalizedSteps.indexWhere(
        (step) => step['id'] == 'runtime',
      );
      final usesRuntime = runtimeIndex >= 0;
      final executionIndex = usesRuntime ? runtimeIndex : fleetIndex;
      final executionStepId = usesRuntime ? 'runtime' : 'fleet';
      final outcomeVariable = usesRuntime
          ? 'RUNTIME_STEP_OUTCOME'
          : 'FLEET_STEP_OUTCOME';
      final stageIndex = normalizedSteps.indexWhere(
        (step) => step['id'] == 'token-stage',
      );
      final finalizer = finalizeIndex >= 0
          ? normalizedSteps[finalizeIndex]
          : null;
      final finalizerRun = finalizer?['run'] as String? ?? '';
      final finalizerIf = finalizer?['if']?.toString() ?? '';
      final finalizerEnv = finalizer?['env'];
      final finalizerUsesPublishedBundle =
          finalizerEnv is Map<String, Object?> &&
          finalizerEnv['AGENT_BUNDLE_ARTIFACT_B64'] ==
              r'${{ steps.' +
                  executionStepId +
                  r'.outputs.agent_bundle_artifact_b64 }}' &&
          finalizerEnv['PUBLISH_STEP_OUTCOME'] ==
              r'${{ steps.publication.outcome }}' &&
          finalizerRun.contains(r'-n "$AGENT_RESULT_B64" &&') &&
          finalizerRun.contains(r'-z "$AGENT_BUNDLE_ARTIFACT_B64" ||') &&
          finalizerRun.contains(r'''"$PUBLISH_STEP_OUTCOME" == 'success' )''');
      final preCleanupTokenSteps = normalizedSteps
          .take(cleanupIndex < 0 ? normalizedSteps.length : cleanupIndex)
          .where((step) {
            final uses = step['uses']?.toString() ?? '';
            return uses.startsWith('actions/create-github-app-token@');
          });
      final noGuestMutationAuthority = preCleanupTokenSteps.every((step) {
        final withValues = step['with'];
        return withValues is Map<String, Object?> &&
            withValues['permission-contents'] != 'write' &&
            withValues['permission-issues'] != 'write' &&
            withValues['permission-pull-requests'] != 'write' &&
            !withValues.containsKey('permission-organization-projects');
      });
      final executionEnv = executionIndex >= 0
          ? normalizedSteps[executionIndex]['env']
          : null;
      final stageEnv = stageIndex >= 0
          ? normalizedSteps[stageIndex]['env']
          : null;
      final noMountedMutationAuthority =
          executionEnv is Map<String, Object?> &&
          stageEnv is Map<String, Object?> &&
          !executionEnv.keys.any(
            (key) => key.contains('PUSH') || key.contains('WRITE'),
          ) &&
          !stageEnv.keys.any(
            (key) => key.contains('PUSH') || key.contains('WRITE'),
          );
      final authorization = authorizationIndex >= 0
          ? normalizedSteps[authorizationIndex]
          : null;
      final authorizationRun = authorization?['run'] as String? ?? '';
      final publication = publicationIndex >= 0
          ? normalizedSteps[publicationIndex]
          : null;
      final publicationEnv = publication?['env'];
      bound =
          gatewayBound &&
          dispatch['environment'] == iiOsAgentEnvironment &&
          permissions.keys.toSet().length == 2 &&
          permissions['contents'] == 'read' &&
          permissions['id-token'] == 'write' &&
          apiWith is Map<String, Object?> &&
          apiWith['permission-contents'] == 'read' &&
          apiWith['permission-issues'] == 'read' &&
          apiWith['permission-pull-requests'] == 'read' &&
          !apiWith.containsKey('permission-organization-projects') &&
          noGuestMutationAuthority &&
          noMountedMutationAuthority &&
          cleanupIndex >= 0 &&
          (fleetIndex >= 0) != (runtimeIndex >= 0) &&
          executionIndex < cleanupIndex &&
          authorizationIndex > cleanupIndex &&
          authorizationRun.contains('/authorize-publication') &&
          authorizationRun.contains('.data.publicationToken') &&
          authorizationRun.contains('.data.publicationAppLogin') &&
          authorizationRun.contains('::add-mask::\$publication_token') &&
          postReadIndex > authorizationIndex &&
          publicationIndex > postReadIndex &&
          publicationEnv is Map<String, Object?> &&
          publicationEnv['GITHUB_PUSH_TOKEN'] ==
              r'${{ steps.publication-authorization.outputs.publication_token }}' &&
          publicationEnv['PUSH_APP_LOGIN'] ==
              r'${{ steps.publication-authorization.outputs.publication_app_login }}' &&
          finalizeIndex > cleanupIndex &&
          finalizeIndex > publicationIndex &&
          finalizerEnv is Map<String, Object?> &&
          finalizerEnv[outcomeVariable] ==
              r'${{ steps.' + executionStepId + r'.outcome }}' &&
          finalizerRun.contains('/finalize') &&
          finalizerRun.contains(
            '''if [[ "\$$outcomeVariable" == 'success' &&''',
          ) &&
          finalizerUsesPublishedBundle &&
          finalizerRun.contains('pull_request: null') &&
          finalizerIf.contains(
            "steps.token-cleanup.outputs.proven == 'true'",
          ) &&
          (usesRuntime
              ? _runtimeWorkflowSecurityBound(normalizedSteps)
              : finalizerIf.contains(
                  "steps.fleet.outputs.fleet_cleanup_proven == 'true'",
                ));
    }
  } on Object {
    bound = false;
  }
  return readinessCheck(
    id: 'agent_job_environment',
    label: 'Agent workflow enforces the post-cleanup broker boundary',
    passed: bound,
    repository: repository,
    detail: bound
        ? 'The credential job gives the guest only read authority, proves cleanup, reauthorizes the exact ticket, then mints fresh trusted publisher tokens and finalizes through ii-os.'
        : 'The agent workflow does not satisfy the exact environment, least-privilege token, cleanup ordering, and broker finalization contract.',
    guidance:
        'Install the current $iiOsAgentTaskWorkflow security contract on dev.',
  );
}

bool _agentWorkTicketGatewayBound(
  Map<String, Object?> root,
  Map<String, Object?> jobs,
) {
  final permissions = root['permissions'];
  final job = jobs['work-ticket'];
  if (permissions is! Map<String, Object?> ||
      permissions.isNotEmpty ||
      job is! Map<String, Object?>) {
    return false;
  }
  final jobPermissions = job['permissions'];
  final withValues = job['with'];
  const expectedInputs = <String, Object?>{
    'operation': 'work_ticket',
    'repository': r'${{ inputs.repository }}',
    'issue_number': r'${{ inputs.issue_number }}',
    'permission_profile': r'${{ inputs.permission_profile }}',
    'permission_ref': r'${{ inputs.permission_ref }}',
    'project_item_id': r'${{ inputs.project_item_id }}',
    'permission_digest': r'${{ inputs.permission_digest }}',
    'dispatch_id': r'${{ inputs.dispatch_id }}',
    'workspace_id': r'${{ inputs.workspace_id }}',
    'codex_secret_digest': r'${{ inputs.codex_secret_digest }}',
    'trusted_source_sha': r'${{ inputs.trusted_source_sha }}',
    'auth_smoke': r'${{ inputs.auth_smoke }}',
    'coordinator_source_sha':
        r'${{ inputs.coordinator_source_sha || github.sha }}',
  };
  return job['if']?.toString().contains("inputs.operation == 'work_ticket'") ==
          true &&
      job['uses'] == './.github/workflows/$iiOsAgentWorkTicketWorkflow' &&
      job['secrets'] == 'inherit' &&
      jobPermissions is Map<String, Object?> &&
      jobPermissions.keys.toSet().length == 2 &&
      jobPermissions['contents'] == 'read' &&
      jobPermissions['id-token'] == 'write' &&
      withValues is Map<String, Object?> &&
      withValues.length == expectedInputs.length &&
      expectedInputs.entries.every(
        (entry) => withValues[entry.key] == entry.value,
      );
}

Object? _yamlObject(Object? value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _yamlObject(entry.value),
    };
  }
  if (value is YamlList) return value.map(_yamlObject).toList();
  return value;
}

bool githubRuntimeEnvironmentProtected(
  Map<String, Object?> environment,
  List<Map<String, Object?>> deploymentPolicies,
  String trustedSourceRef,
) {
  final rules = environment['protection_rules'];
  final normalizedRules = rules is List<Object?>
      ? rules.whereType<Map<String, Object?>>().toList()
      : const <Map<String, Object?>>[];
  final branchPolicy =
      normalizedRules.where((rule) => rule['type'] == 'branch_policy').length ==
      1;
  final noReviewGate = normalizedRules.every(
    (rule) => rule['type'] != 'required_reviewers',
  );
  final policy = environment['deployment_branch_policy'];
  final exactPolicy =
      policy is Map<String, Object?> &&
      policy['protected_branches'] == false &&
      policy['custom_branch_policies'] == true &&
      deploymentPolicies.length == 1 &&
      deploymentPolicies.single['type'] == 'tag' &&
      RegExp(r'^ii-os-agent-v4-[0-9a-f]{40}$').hasMatch(trustedSourceRef) &&
      deploymentPolicies.single['name'] == trustedSourceRef;
  return environment['can_admins_bypass'] == false &&
      branchPolicy &&
      noReviewGate &&
      exactPolicy;
}

bool githubBootstrapEnvironmentProtected(
  Map<String, Object?> environment,
  List<Map<String, Object?>> deploymentPolicies,
) {
  final rules = environment['protection_rules'];
  final normalizedRules = rules is List<Object?>
      ? rules.whereType<Map<String, Object?>>().toList()
      : const <Map<String, Object?>>[];
  final branchPolicy =
      normalizedRules.where((rule) => rule['type'] == 'branch_policy').length ==
      1;
  final noReviewGate = normalizedRules.every(
    (rule) => rule['type'] != 'required_reviewers',
  );
  final policy = environment['deployment_branch_policy'];
  final exactPolicy =
      policy is Map<String, Object?> &&
      policy['protected_branches'] == false &&
      policy['custom_branch_policies'] == true &&
      deploymentPolicies.length == 1 &&
      deploymentPolicies.single['type'] == 'tag' &&
      deploymentPolicies.single['name'] == 'ii-os-agent-v4-bootstrap-*';
  return environment['can_admins_bypass'] == false &&
      branchPolicy &&
      noReviewGate &&
      exactPolicy;
}

bool githubTrustedTagRulesetProtected(List<Object?> rulesets) =>
    rulesets.any((rawRuleset) {
      final bypass = _stringObjectMap(rawRuleset)?['bypass_actors'];
      return _githubTrustedTagRulesetStructureProtected(rawRuleset) &&
          bypass is List<Object?> &&
          bypass.isEmpty;
    });

bool githubTrustedTagRulesetBypassHidden(List<Object?> rulesets) =>
    rulesets.any((rawRuleset) {
      final ruleset = _stringObjectMap(rawRuleset);
      return _githubTrustedTagRulesetStructureProtected(rawRuleset) &&
          !ruleset!.containsKey('bypass_actors') &&
          ruleset['current_user_can_bypass'] == 'never';
    });

bool _githubTrustedTagRulesetStructureProtected(Object? rawRuleset) {
  final ruleset = _stringObjectMap(rawRuleset);
  final conditions = _stringObjectMap(ruleset?['conditions']);
  final refName = _stringObjectMap(conditions?['ref_name']);
  final include = refName?['include'];
  final exclude = refName?['exclude'];
  final rawRules = ruleset?['rules'];
  final ruleTypes = rawRules is List<Object?>
      ? rawRules
            .map(_stringObjectMap)
            .nonNulls
            .map((rule) => rule['type'])
            .toSet()
      : const <Object?>{};
  return ruleset?['target'] == 'tag' &&
      ruleset?['enforcement'] == 'active' &&
      include is List<Object?> &&
      include.contains('refs/tags/ii-os-agent-v4-*') &&
      exclude is List<Object?> &&
      exclude.isEmpty &&
      ruleTypes.containsAll(const {'update', 'deletion'});
}

Map<String, Object?>? _stringObjectMap(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    result[key] = entry.value;
  }
  return result;
}

Map<String, Object?> trustedAgentSourceManifestCheck(
  Map<String, String> actual,
  Map<String, String> expected, {
  required String repository,
  Map<String, String> actualModes = const {},
  Map<String, String> expectedModes = const {},
}) {
  final blobsExact =
      actual.length == expected.length &&
      actual.keys.toSet().containsAll(expected.keys) &&
      expected.entries.every((entry) => actual[entry.key] == entry.value);
  final modesExact =
      expectedModes.isEmpty ||
      (actualModes.length == expectedModes.length &&
          actualModes.keys.toSet().containsAll(expectedModes.keys) &&
          expectedModes.entries.every(
            (entry) => actualModes[entry.key] == entry.value,
          ));
  final exact = blobsExact && modesExact;
  final mismatchedPaths = <String>{
    ...actual.keys.where(
      (path) => !expected.containsKey(path) || expected[path] != actual[path],
    ),
    ...expected.keys.where(
      (path) => !actual.containsKey(path) || actual[path] != expected[path],
    ),
    ...actualModes.keys.where(
      (path) =>
          expectedModes.containsKey(path) &&
          expectedModes[path] != actualModes[path],
    ),
    ...expectedModes.keys.where(
      (path) =>
          !actualModes.containsKey(path) ||
          actualModes[path] != expectedModes[path],
    ),
  }.toList()..sort();
  return readinessCheck(
    id: 'trusted_agent_source_manifest',
    label: 'Agent source matches the reviewed security manifest',
    passed: exact,
    repository: repository,
    detail: exact
        ? 'Every workflow and executable helper matches its reviewed Git blob.'
        : 'Trusted source changed: ${mismatchedPaths.join(', ')}.',
    guidance: exact
        ? ''
        : 'A trusted maintainer must review these exact changes and update the ii-os source manifest. Running the installer again cannot clear this check.',
  );
}

Map<String, Object?> trustedPythonImportNamespaceCheck(
  Map<String, Set<String>> actual, {
  required String repository,
  required Map<String, Set<String>> expected,
}) {
  final exact =
      actual.keys.toSet().length == expected.length &&
      actual.keys.toSet().containsAll(expected.keys) &&
      expected.entries.every(
        (entry) =>
            actual[entry.key]?.length == entry.value.length &&
            actual[entry.key]!.containsAll(entry.value),
      );
  return readinessCheck(
    id: 'trusted_python_import_namespace',
    label: 'Python helper imports contain only reviewed source',
    passed: exact,
    repository: repository,
    detail: exact
        ? 'Every importable sibling and package entry is reviewed.'
        : 'An added, removed, or renamed Python import entry can shadow reviewed helper code.',
    guidance: exact
        ? ''
        : 'Remove unreviewed import entries and reinstall the reviewed ii-os agent source set.',
  );
}

bool codexSecretMetadataMatches(String current, String validated) {
  final currentTime = DateTime.tryParse(current)?.toUtc();
  final validatedTime = DateTime.tryParse(validated)?.toUtc();
  return currentTime != null &&
      validatedTime != null &&
      currentTime == validatedTime;
}

List<Map<String, Object?>> repositoryWorkflowChecks(
  List<Map<String, Object?>> workflows, {
  required String repository,
}) {
  Map<String, Object?> check({
    required String id,
    required String label,
    required String file,
  }) {
    final workflow = workflows.where((item) {
      final path = item['path'];
      return path is String && path.endsWith('/$file');
    }).firstOrNull;
    final active = workflow?['state'] == 'active';
    return readinessCheck(
      id: id,
      label: label,
      passed: active,
      repository: repository,
      detail: active
          ? 'GitHub reports $file as active.'
          : workflow == null
          ? 'GitHub could not find $file.'
          : 'GitHub reports this workflow as ${workflow['state']}.',
      guidance:
          'Add .github/workflows/$file on dev and enable it in the Actions tab.',
    );
  }

  return [
    check(
      id: 'permission_installer_workflow',
      label: 'Permission installer workflow is active',
      file: iiOsAgentPermissionInstallerWorkflow,
    ),
    check(
      id: 'agent_workflow',
      label: 'Agent task workflow is active',
      file: iiOsAgentTaskWorkflow,
    ),
    check(
      id: 'codex_auth_workflow',
      label: 'Codex verification workflow is active',
      file: iiOsCodexAuthWorkflow,
    ),
    check(
      id: 'codex_auth_finalize_workflow',
      label: 'Codex cleanup finalizer is active',
      file: iiOsCodexAuthFinalizeWorkflow,
    ),
  ];
}

bool _isExecutableProfile(AgentPermissionProfile profile) {
  try {
    requireExecutableAgentProfile(profile);
    return true;
  } on ApiError {
    return false;
  }
}

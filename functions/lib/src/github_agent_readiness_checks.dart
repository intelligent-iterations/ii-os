part of 'github_client.dart';

Map<String, Object?> permissionInstallerProofCheck(
  List<Map<String, Object?>> runs, {
  required String repository,
  required AgentPermissionProfile profile,
  required Object? proof,
  required Map<String, String> currentWorkflowBlobShas,
  required Map<String, String> currentWorkflowModes,
  required String currentSourceSha,
  required AgentTrustedSourceManifest sourceManifest,
  DateTime Function()? clock,
}) {
  final expectedDigest = agentPermissionProfileDigest(profile);
  final expectedTitle = RegExp(
    '^ii-os permission v4 / [A-Za-z0-9_-]{1,128} / '
    '[A-Za-z0-9_-]{20,128} / ${RegExp.escape(profile.id)}@'
    '${RegExp.escape(profile.version)} / $expectedDigest / '
    r'bootstrap@[0-9a-f]{40}$',
  );
  final matching = runs
      .where(
        (run) =>
            expectedTitle.hasMatch(run['display_title'] as String? ?? '') &&
            run['event'] == 'workflow_dispatch' &&
            run['head_branch'] ==
                'ii-os-agent-v4-bootstrap-${run['head_sha']}' &&
            RegExp(
              r'^[0-9a-f]{40}$',
            ).hasMatch(run['head_sha'] as String? ?? '') &&
            run['path'] ==
                '.github/workflows/$iiOsAgentPermissionInstallerWorkflow',
      )
      .toList();
  matching.sort(
    (left, right) => ((right['run_number'] as num?)?.toInt() ?? 0).compareTo(
      (left['run_number'] as num?)?.toInt() ?? 0,
    ),
  );
  final run = matching.firstOrNull;
  final parsedProof = proof is Map
      ? proof.cast<String, Object?>()
      : const <String, Object?>{};
  final proofKeys = parsedProof.keys.toSet();
  final workflowProof = parsedProof['trusted_source_blob_shas'];
  final proofShas = workflowProof is Map
      ? workflowProof.cast<String, Object?>()
      : const <String, Object?>{};
  final modeProof = parsedProof['trusted_source_modes'];
  final proofModes = modeProof is Map
      ? modeProof.cast<String, Object?>()
      : const <String, Object?>{};
  final namespaceShaProof = parsedProof['workflow_namespace_blob_shas'];
  final namespaceShas = namespaceShaProof is Map
      ? namespaceShaProof.cast<String, Object?>()
      : const <String, Object?>{};
  final namespaceModeProof = parsedProof['workflow_namespace_modes'];
  final namespaceModes = namespaceModeProof is Map
      ? namespaceModeProof.cast<String, Object?>()
      : const <String, Object?>{};
  final workflowNames = sourceManifest.sourcePaths.toSet();
  final createdAt = DateTime.tryParse(
    run?['created_at'] as String? ?? '',
  )?.toUtc();
  final now = (clock ?? _readinessUtcNow)().toUtc();
  final fresh =
      createdAt != null &&
      !createdAt.isAfter(now.add(const Duration(seconds: 30))) &&
      now.difference(createdAt) <= const Duration(days: 30);
  final passed =
      run != null &&
      run['status'] == 'completed' &&
      run['conclusion'] == 'success' &&
      fresh &&
      proofKeys.length == (profile.runtime == null ? 15 : 16) &&
      proofKeys.containsAll({
        'schema_version',
        'security_contract',
        'approval_id',
        'dispatch_id',
        'profile_id',
        'profile_version',
        'profile_digest',
        'installer_run_id',
        'installer_run_attempt',
        'installer_source_sha',
        'trusted_source_blob_shas',
        'trusted_source_modes',
        'workflow_namespace_blob_shas',
        'workflow_namespace_modes',
        if (profile.runtime == null) 'runtime_image',
        if (profile.runtime != null) 'runtime_configuration_sha256',
        if (profile.runtime != null) 'execution_binding_sha256',
      }) &&
      parsedProof['schema_version'] == (profile.runtime == null ? 1 : 2) &&
      parsedProof['security_contract'] == iiOsAgentSecurityContract &&
      _identifier.hasMatch('${parsedProof['approval_id']}') &&
      _dispatchIdentifier.hasMatch('${parsedProof['dispatch_id']}') &&
      namespaceShas.isNotEmpty &&
      namespaceShas.keys.every(
        (name) =>
            namespaceShas[name] is String &&
            RegExp(
              r'^[0-9a-f]{40}$',
            ).hasMatch(namespaceShas[name]! as String) &&
            namespaceModes[name] == '100644',
      ) &&
      namespaceShas.keys.toSet().containsAll(
        workflowNames.where((name) => name.startsWith('.github/workflows/')),
      ) &&
      parsedProof['profile_id'] == profile.id &&
      parsedProof['profile_version'] == profile.version &&
      parsedProof['profile_digest'] == expectedDigest &&
      parsedProof['installer_run_id'] == run['id'] &&
      parsedProof['installer_run_attempt'] == run['run_attempt'] &&
      parsedProof['installer_source_sha'] == run['head_sha'] &&
      (profile.runtime == null
          ? parsedProof['runtime_image'] == profile.fleet.image
          : parsedProof['runtime_configuration_sha256'] ==
                    profile.runtime!.configurationDigest &&
                parsedProof['execution_binding_sha256'] ==
                    profile.runtime!.bindingDigest) &&
      proofShas.keys.toSet().length == workflowNames.length &&
      proofShas.keys.toSet().containsAll(workflowNames) &&
      proofModes.keys.toSet().length == workflowNames.length &&
      proofModes.keys.toSet().containsAll(workflowNames) &&
      currentWorkflowBlobShas.keys.toSet().length == workflowNames.length &&
      currentWorkflowModes.keys.toSet().length == workflowNames.length &&
      workflowNames.every(
        (name) =>
            proofShas[name] is String &&
            RegExp(r'^[0-9a-f]{40}$').hasMatch(proofShas[name]! as String) &&
            currentWorkflowBlobShas[name] == proofShas[name] &&
            proofModes[name] == sourceManifest.modes[name] &&
            currentWorkflowModes[name] == proofModes[name],
      );
  final runStatus = run == null
      ? 'not_started'
      : run['status'] != 'completed'
      ? 'running'
      : passed
      ? 'succeeded'
      : run['conclusion'] == 'success'
      ? 'verification_failed'
      : 'failed';
  final detail = run == null
      ? 'No exact v7 Fleet-backed installation matches this profile digest.'
      : run['status'] != 'completed'
      ? 'The latest exact installer is ${run['status']}; no permission proof is accepted until it completes.'
      : run['conclusion'] != 'success'
      ? 'The latest exact installer completed with ${run['conclusion']}; no permission proof was accepted.'
      : !fresh
      ? 'The matching installer proof is older than 30 days.'
      : run['head_sha'] != currentSourceSha
      ? 'Dev advanced from ${_shortSha(run['head_sha'])} to ${_shortSha(currentSourceSha)} after this installer started. Dispatch a new installation for current dev.'
      : parsedProof.isEmpty
      ? 'The installer run succeeded, but dev does not contain .ii-os/agent-permission-proofs/${profile.id}.json. The run did not publish durable installation proof.'
      : passed
      ? 'The latest exact v7 run succeeded after Fleet cleanup and binds this profile, runtime image, and every executable current-dev source blob.'
      : 'The latest matching v7 run, committed proof, runtime image, profile digest, or executable current-dev source blobs do not agree.';
  return {
    ...readinessCheck(
      id: 'permission_installer_proof',
      label: 'Permission installer is bound to current dev',
      passed: passed,
      repository: repository,
      detail: detail,
      guidance: passed
          ? ''
          : 'Run the current installer for this exact profile and wait for its Fleet cleanup proof.',
    ),
    'runStatus': runStatus,
    if (run?['head_sha'] case final String sha) 'runSourceSha': sha,
    if (run?['html_url'] case final String url when url.isNotEmpty)
      'runUrl': url,
  };
}

String _shortSha(Object? value) {
  final text = value?.toString() ?? '';
  return text.length >= 8 ? text.substring(0, 8) : text;
}

/// Proof contract the repository-owned installer writes.
const int iiOsAgentSecurityContract = 7;

final _identifier = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final _dispatchIdentifier = RegExp(r'^[A-Za-z0-9_-]{20,128}$');

DateTime _readinessUtcNow() => DateTime.now().toUtc();

/// App permissions, as (label, level, guidance, blocks agent setup).
const githubAppPermissionRequirements =
    <String, (String, String, String, bool)>{
      'actions': (
        'GitHub App can start approved CI/CD workflows',
        'write',
        'Set repository permission Actions to Read and write.',
        true,
      ),
      'contents': (
        'GitHub App can read and write repository content',
        'write',
        'Set repository permission Contents to Read and write.',
        true,
      ),
      'deployments': (
        'GitHub App can verify the deployed dev build',
        'read',
        'Set repository permission Deployments to Read-only.',
        false,
      ),
      'pull_requests': (
        'GitHub App can create and update pull requests',
        'write',
        'Set repository permission Pull requests to Read and write.',
        true,
      ),
    };

const githubWorkshopPermissionRequirements =
    <String, (String, String, String, bool)>{
      'issues': (
        'GitHub App can read and update Workshop issues',
        'write',
        'Set repository permission Issues to Read and write.',
        true,
      ),
      'organization_projects': (
        'GitHub App can read and update the Workshop Project',
        'write',
        'Set organization permission Projects to Read and write.',
        true,
      ),
    };

List<Map<String, Object?>> githubAppPermissionChecks(
  Map<String, String> permissions, {
  bool requiresWorkshop = false,
}) {
  final requirements = {
    ...githubAppPermissionRequirements,
    if (requiresWorkshop) ...githubWorkshopPermissionRequirements,
  };
  return requirements.entries.map((entry) {
    final actual = permissions[entry.key] ?? 'none';
    final required = entry.value.$2;
    final passed = _permissionAllows(actual, required);
    return {
      ...readinessCheck(
        id: 'github_app_${entry.key}',
        label: entry.value.$1,
        passed: passed,
        detail: passed
            ? 'Granted: $actual.'
            : 'Granted: $actual; required: $required.',
        guidance: entry.value.$3,
      ),
      if (!passed && !entry.value.$4) 'status': 'warning',
      'currentValue': _permissionDisplayName(actual),
      'requiredValue': _permissionDisplayName(required),
    };
  }).toList();
}

String _permissionDisplayName(String value) => switch (value) {
  'read' => 'Read-only',
  'write' => 'Read and write',
  _ => 'No access',
};

/// Names of permissions the installation is missing.
Set<String> missingGitHubAppPermissions(
  Map<String, String> permissions, {
  bool requiresWorkshop = false,
}) => {
  for (final entry in {
    ...githubAppPermissionRequirements,
    if (requiresWorkshop) ...githubWorkshopPermissionRequirements,
  }.entries)
    if (!_permissionAllows(permissions[entry.key] ?? 'none', entry.value.$2))
      entry.key,
};

/// Whether widening the App's own permissions is what remains to be done.
///
/// GitHub applies an App permission change to an installation only after an
/// owner accepts it, so a missing permission has two very different remedies.
/// When the App itself still lacks the permission the owner edits the App; once
/// the App has it, every remaining gap is an unaccepted installation request
/// and editing the App again changes nothing.
bool githubAppPermissionEditPending({
  required Map<String, String> appPermissions,
  required Map<String, String> installationPermissions,
  bool requiresWorkshop = false,
}) =>
    missingGitHubAppPermissions(
      installationPermissions,
      requiresWorkshop: requiresWorkshop,
    ).any(
      (name) => !_permissionAllows(
        appPermissions[name] ?? 'none',
        ({
          ...githubAppPermissionRequirements,
          if (requiresWorkshop) ...githubWorkshopPermissionRequirements,
        })[name]!.$2,
      ),
    );

List<Map<String, Object?>> agentProfileChecks(
  AgentPermissionProfile? profile, {
  required String repository,
  AgentEngineCatalog engines = AgentEngineCatalog.codexOnly,
}) {
  if (profile?.runtime != null) {
    return [
      readinessCheck(
        id: 'runtime_configuration',
        label: 'Agent runtime configuration is pinned',
        passed: true,
        repository: repository,
        detail:
            'The approved profile pins runtime configuration and its execution binding by content hash.',
        guidance:
            'Update the reviewed runtime files and their profile hashes together when changing execution settings.',
      ),
    ];
  }
  final capabilities = profile?.fleet.capabilities.toSet() ?? const <String>{};
  final engine = profile?.engine ?? codexAgentEngine;
  final missing = agentCapabilitiesForEngine(
    engine,
    engines,
  ).difference(capabilities);
  final hasRuntime = capabilities.any((item) => item.startsWith('runtime-'));
  final binding = profile?.secretInjection.bindings
      .where(
        (item) =>
            item.capability == 'codex-oauth' &&
            item.githubSecret == 'CODEX_AUTH_JSON',
      )
      .firstOrNull;
  final usageBinding = profile?.secretInjection.bindings
      .where(
        (item) =>
            item.capability == 'agent-usage-reporting' &&
            item.githubSecret == 'II_OS_AGENT_USAGE_API_KEY',
      )
      .firstOrNull;
  return [
    readinessCheck(
      id: 'fleet_capabilities',
      label: 'Agent runtime capabilities declared',
      passed: profile != null && missing.isEmpty && hasRuntime,
      repository: repository,
      detail: profile == null
          ? 'Install a profile before capabilities can be checked.'
          : missing.isEmpty && hasRuntime
          ? agentEngineUsesCodexOAuth(engine)
                ? 'Runtime, Codex OAuth, GitHub token, and usage reporting capabilities are declared.'
                : 'The local model runtime, model cache, GitHub token, and usage reporting capabilities are declared.'
          : 'Missing: ${[...missing, if (!hasRuntime) 'runtime-docker'].join(', ')}.',
      guidance:
          'Add the missing names to fleet.capabilities in the agent permission profile.',
    ),
    if (engine == codexAgentEngine)
      readinessCheck(
        id: 'codex_secret_binding',
        label: 'Codex OAuth secret is bound to the agent',
        passed: binding != null,
        repository: repository,
        detail: binding == null
            ? 'CODEX_AUTH_JSON is not bound to the codex-oauth capability.'
            : 'CODEX_AUTH_JSON will be injected as ${binding.targetName}.',
        guidance:
            'Add a codex-oauth secret binding for CODEX_AUTH_JSON to the profile.',
      ),
    readinessCheck(
      id: 'agent_usage_secret_binding',
      label: 'Agent usage reporting key is bound to the agent',
      passed: usageBinding != null,
      repository: repository,
      detail: usageBinding == null
          ? 'II_OS_AGENT_USAGE_API_KEY is not bound to agent-usage-reporting.'
          : 'The write-only usage key will be injected as ${usageBinding.targetName}.',
      guidance:
          'Add an agent-usage-reporting file binding for II_OS_AGENT_USAGE_API_KEY.',
    ),
  ];
}

/// The bootstrap-marker check, carrying the command that clears it.
///
/// ii-os deliberately does not mint this marker. A human-review proof created
/// by the reviewed system proves nothing, even when the App can publish
/// reviewed changes elsewhere. So this is the one check the operator satisfies
/// entirely outside ii-os, and the exact tag and command are the difference
/// between a task and a wall. [missingDetails] is the
/// `permission_bootstrap_tag_missing` payload, which already computed both.
Map<String, Object?> bootstrapTagCheck({
  required String repository,
  required String? tag,
  Map<String, Object?> missingDetails = const {},
}) {
  final expectedTag = missingDetails['tag'];
  final command = missingDetails['command'];
  return {
    ...readinessCheck(
      id: 'permission_bootstrap_tag',
      label: 'Repository is marked ready to install permissions',
      passed: tag != null,
      repository: repository,
      detail: tag != null
          ? 'This repository is marked ready at its current dev commit.'
          : 'This repository has no release marker on its current dev commit, '
                'so permissions cannot be installed yet.',
      guidance:
          'Someone with write access to $repository creates the marker once '
          'per dev commit. ii-os cannot create it, because the marker is what '
          'proves the installer code was reviewed.',
    ),
    'currentValue': tag ?? 'No marker on this commit',
    if (expectedTag is String && expectedTag.isNotEmpty)
      'requiredValue': expectedTag,
    if (command is String && command.isNotEmpty) 'command': command,
  };
}

Map<String, Object?> readinessCheck({
  required String id,
  required String label,
  required bool passed,
  required String detail,
  required String guidance,
  String? repository,
  String? action,
}) => {
  'id': id,
  'label': label,
  'status': passed ? 'passed' : 'action_required',
  'detail': detail,
  if (!passed && guidance.isNotEmpty) 'guidance': guidance,
  'repository': ?repository,
  'action': ?action,
};

Map<String, Object?> readinessFromGitHubError({
  required String id,
  required String label,
  required String repository,
  required ApiError error,
  required Set<String> missingCodes,
  required String guidance,
}) => missingCodes.contains(error.code)
    ? readinessCheck(
        id: id,
        label: label,
        passed: false,
        repository: repository,
        detail: error.message,
        guidance: guidance,
      )
    : readinessUnable(
        id: id,
        label: label,
        repository: repository,
        error: error,
        guidance: guidance,
      );

Map<String, Object?> readinessUnable({
  required String id,
  required String label,
  required String repository,
  required ApiError error,
  required String guidance,
}) => {
  'id': id,
  'label': label,
  'status': 'unable_to_verify',
  'detail': error.message,
  'guidance': guidance,
  'repository': repository,
};

bool _permissionAllows(String actual, String required) =>
    actual == 'write' || actual == required;

part of 'github_client.dart';

final class AgentRepositoryReadinessInspection {
  const AgentRepositoryReadinessInspection({
    required this.sourceSha,
    required this.sourceRef,
    required this.engine,
    required this.checks,
  });

  final String sourceSha;
  final String sourceRef;
  final String engine;
  final List<Map<String, Object?>> checks;
}

extension GitHubAgentReadiness on GitHubClient {
  Future<AgentRepositoryReadinessInspection> inspectAgentRepositoryReadiness(
    Workspace workspace, {
    required String repository,
    Map<String, Object?>? codexAuthState,
    TrustedTagRulesetAttestation? tagRulesetAttestation,
    String? permissionProfileId,
    String? requiredEngine,
  }) async {
    final permissions = await _transport.installationPermissions(
      workspace,
      refresh: true,
      repository: repository,
    );
    final inspected = await _inspectAgentRepository(
      workspace,
      repository: repository,
      permissions: permissions,
      codexAuthState: codexAuthState,
      tagRulesetAttestation: tagRulesetAttestation,
      permissionProfileId: permissionProfileId,
      requiredEngine: requiredEngine,
    );
    return AgentRepositoryReadinessInspection(
      sourceSha: inspected.sourceSha,
      sourceRef: inspected.sourceRef,
      engine: inspected.engine,
      checks: [
        ...githubAppPermissionChecks(
          permissions,
          requiresWorkshop: workspace.projects.isNotEmpty,
        ),
        ...agentDispatchReadinessChecks(
          inspected.checks,
          engine: inspected.engine,
        ),
      ],
    );
  }

  Future<List<Map<String, Object?>>> inspectAgentReadiness(
    Workspace workspace, {
    Map<String, Map<String, Object?>?> codexAuthStates = const {},
  }) async {
    final checks = <Map<String, Object?>>[];
    final permissions = await _transport.installationPermissions(
      workspace,
      refresh: true,
    );
    checks.addAll(
      githubAppPermissionChecks(
        permissions,
        requiresWorkshop: workspace.projects.isNotEmpty,
      ),
    );
    for (final repository in workspace.repositories) {
      final inspected = await _inspectAgentRepository(
        workspace,
        repository: repository,
        permissions: permissions,
        codexAuthState: codexAuthStates[repository],
      );
      checks.addAll(inspected.checks);
    }
    return checks;
  }

  Future<AgentRepositoryReadinessInspection> _inspectAgentRepository(
    Workspace workspace, {
    required String repository,
    required Map<String, String> permissions,
    required Map<String, Object?>? codexAuthState,
    TrustedTagRulesetAttestation? tagRulesetAttestation,
    String? permissionProfileId,
    String? requiredEngine,
  }) async {
    final checks = <Map<String, Object?>>[];
    var sourceSha = '';
    var sourceRef = '';
    var installerActive = false;
    final currentWorkflowBlobShas = <String, String>{};
    final currentWorkflowModes = <String, String>{};
    final currentPythonImportNamespaces = <String, Set<String>>{};
    final workflowAllowed = workspace.workflows.contains(
      '$repository#$iiOsAgentTaskWorkflow',
    );
    checks.add(
      readinessCheck(
        id: 'workflow_allowlist',
        label: 'Agent workflow enabled in ii-os',
        passed: workflowAllowed,
        repository: repository,
        detail: workflowAllowed
            ? '$iiOsAgentTaskWorkflow is enabled for dispatch.'
            : '$iiOsAgentTaskWorkflow is not in the workspace workflow allowlist.',
        guidance:
            'Open workspace access and enable $iiOsAgentTaskWorkflow for this repository.',
      ),
    );
    checks.add(
      readinessCheck(
        id: 'agent_source_configuration',
        label: 'Agent executable source manifest configured',
        passed: agentTrustedSourceManifest.configured,
        repository: repository,
        detail: agentTrustedSourceManifest.configured
            ? 'This deployment supplied a reviewed executable source manifest.'
            : 'This deployment did not supply an executable source manifest.',
        guidance: agentTrustedSourceManifest.configured
            ? ''
            : 'Configure a reviewed agent source manifest in the implementation repository.',
      ),
    );
    if (!agentTrustedSourceManifest.configured) {
      return AgentRepositoryReadinessInspection(
        sourceSha: '',
        sourceRef: '',
        engine: requiredEngine ?? codexAgentEngine,
        checks: checks,
      );
    }

    if (!_permissionAllows(permissions['actions'] ?? 'none', 'read')) {
      checks.addAll([
        readinessCheck(
          id: 'agent_workflow',
          label: 'Agent task workflow is active',
          passed: false,
          repository: repository,
          detail: 'The GitHub App cannot inspect repository workflows.',
          guidance: 'Set the GitHub App Actions permission to Read and write.',
        ),
        readinessCheck(
          id: 'codex_auth_workflow',
          label: 'Codex verification workflow is active',
          passed: false,
          repository: repository,
          detail: 'The GitHub App cannot inspect repository workflows.',
          guidance: 'Set the GitHub App Actions permission to Read and write.',
        ),
      ]);
    } else {
      try {
        final workflows = await listRepositoryWorkflows(workspace, repository);
        checks.addAll(
          repositoryWorkflowChecks(workflows, repository: repository),
        );
        installerActive = workflows.any(
          (item) =>
              item['path'] ==
                  '.github/workflows/$iiOsAgentPermissionInstallerWorkflow' &&
              item['state'] == 'active',
        );
        if (_permissionAllows(permissions['contents'] ?? 'none', 'read')) {
          try {
            final resolved = await _resolveTrustedAgentSource(
              workspace,
              repository,
            );
            sourceSha = resolved.$1;
            sourceRef = resolved.$2;
            checks.add(resolved.$3);
            final encodedRef = Uri.encodeQueryComponent(sourceSha);
            final treeResponse = _asMap(
              await _rest(
                workspace,
                'GET',
                '/repos/$repository/git/trees/$encodedRef?recursive=1',
              ),
            );
            final rawTree = treeResponse['tree'];
            if (treeResponse['truncated'] != false ||
                rawTree is! List<Object?>) {
              throw const ApiError(
                502,
                'github_response_invalid',
                'GitHub returned an incomplete agent source tree.',
              );
            }
            final sourceEntries = <String, Map<String, Object?>>{};
            for (final rawEntry in rawTree) {
              if (rawEntry is! Map<String, Object?> ||
                  rawEntry['path'] is! String ||
                  rawEntry['type'] is! String ||
                  rawEntry['mode'] is! String ||
                  rawEntry['sha'] is! String) {
                throw const ApiError(
                  502,
                  'github_response_invalid',
                  'GitHub returned an unreadable agent source tree entry.',
                );
              }
              sourceEntries[rawEntry['path']! as String] = rawEntry;
            }
            for (final path in agentTrustedSourceManifest.sourcePaths) {
              final entry = sourceEntries[path];
              final blobSha = entry?['sha'];
              final mode = entry?['mode'];
              if (entry?['type'] != 'blob' ||
                  (mode != '100644' && mode != '100755') ||
                  blobSha is! String ||
                  !RegExp(r'^[0-9a-f]{40}$').hasMatch(blobSha)) {
                throw const ApiError(
                  502,
                  'github_response_invalid',
                  'GitHub returned a non-regular or unreadable agent source.',
                );
              }
              currentWorkflowBlobShas[path] = blobSha;
              currentWorkflowModes[path] = mode as String;
            }
            final agentSource = await _trustedWorkflowSource(
              workspace,
              repository: repository,
              encodedRef: encodedRef,
              workflow: iiOsAgentTaskWorkflow,
              expectedBlobShas: currentWorkflowBlobShas,
            );
            final workTicketSource = await _trustedWorkflowSource(
              workspace,
              repository: repository,
              encodedRef: encodedRef,
              workflow: iiOsAgentWorkTicketWorkflow,
              expectedBlobShas: currentWorkflowBlobShas,
            );
            for (final directory
                in agentTrustedSourceManifest.pythonImportNamespaces.keys) {
              final prefix = '$directory/';
              final reviewedDirectories = {
                for (final child
                    in agentTrustedSourceManifest.pythonImportNamespaces.keys)
                  if (child.startsWith(prefix) &&
                      !child.substring(prefix.length).contains('/'))
                    child.substring(prefix.length),
              };
              final importEntries = <String>{};
              for (final entry in sourceEntries.entries) {
                if (!entry.key.startsWith(prefix)) continue;
                final name = entry.key.substring(prefix.length);
                if (name.isEmpty || name.contains('/')) continue;
                final candidate = {...entry.value, 'name': name};
                if (pythonImportCandidate(
                  candidate,
                  reviewedDirectories: reviewedDirectories,
                )) {
                  importEntries.add(pythonImportEntryIdentity(candidate));
                }
              }
              currentPythonImportNamespaces[directory] = importEntries;
            }
            checks.add(
              trustedAgentSourceManifestCheck(
                currentWorkflowBlobShas,
                agentTrustedSourceManifest.blobShas,
                repository: repository,
                actualModes: currentWorkflowModes,
                expectedModes: agentTrustedSourceManifest.modes,
              ),
            );
            checks.add(
              trustedPythonImportNamespaceCheck(
                currentPythonImportNamespaces,
                repository: repository,
                expected: agentTrustedSourceManifest.pythonImportNamespaces,
              ),
            );
            if (_permissionAllows(
              permissions['administration'] ?? 'none',
              'read',
            )) {
              checks.add(
                await _trustedTagProtectionCheck(
                  workspace,
                  repository: repository,
                  attestation: tagRulesetAttestation,
                ),
              );
            } else {
              checks.add(
                readinessCheck(
                  id: 'immutable_tag_protection',
                  label: 'Trusted agent tags cannot be changed',
                  passed: false,
                  repository: repository,
                  detail:
                      'The GitHub App cannot inspect repository tag rulesets.',
                  guidance:
                      'Set the GitHub App Administration permission to Read-only.',
                ),
              );
            }
            checks.add(
              agentWorkflowEnvironmentCheck(
                agentSource,
                workTicketSource: workTicketSource,
                repository: repository,
              ),
            );
          } on ApiError catch (error) {
            checks.add(
              readinessUnable(
                id: 'agent_job_environment',
                label: 'Agent job is bound to its credential environment',
                repository: repository,
                error: error,
                guidance:
                    'Bind the secret-bearing dispatch job to $iiOsAgentEnvironment.',
              ),
            );
          }
        }
      } on ApiError catch (error) {
        checks.addAll([
          readinessUnable(
            id: 'permission_installer_workflow',
            label: 'Permission installer workflow is active',
            repository: repository,
            error: error,
            guidance:
                'Grant the GitHub App Actions read/write access, then retry the check.',
          ),
          readinessUnable(
            id: 'agent_workflow',
            label: 'Agent task workflow is active',
            repository: repository,
            error: error,
            guidance:
                'Grant the GitHub App Actions read/write access, then retry the check.',
          ),
          readinessUnable(
            id: 'codex_auth_workflow',
            label: 'Codex verification workflow is active',
            repository: repository,
            error: error,
            guidance:
                'Grant the GitHub App Actions read/write access, then retry the check.',
          ),
          readinessUnable(
            id: 'codex_auth_finalize_workflow',
            label: 'Codex cleanup finalizer is active',
            repository: repository,
            error: error,
            guidance:
                'Grant the GitHub App Actions read/write access, then retry the check.',
          ),
        ]);
      }
    }

    AgentPermissionProfile? profile;
    if (!_permissionAllows(permissions['contents'] ?? 'none', 'read')) {
      checks.add(
        readinessCheck(
          id: 'permission_profile',
          label: 'Agent permission profile installed',
          passed: false,
          repository: repository,
          detail: 'The GitHub App cannot read repository configuration.',
          guidance: 'Set the GitHub App Contents permission to Read-only.',
        ),
      );
    } else {
      try {
        final profiles = await listAgentPermissionProfiles(
          workspace,
          repository: repository,
          ref: sourceSha,
        );
        final parsed = profiles.map(agentPermissionProfileFromListing).toList();
        final candidates = parsed
            .where((item) => item.workflow.file == iiOsAgentTaskWorkflow)
            .toList();
        profile = candidates
            .where(_isExecutableProfile)
            .where(
              (item) =>
                  (permissionProfileId == null ||
                      item.id == permissionProfileId) &&
                  (requiredEngine == null || item.engine == requiredEngine),
            )
            .firstOrNull;
        checks.add(
          readinessCheck(
            id: 'permission_profile',
            label: 'Executable agent permission profile installed',
            passed: profile != null,
            repository: repository,
            detail: profile == null
                ? candidates.isEmpty
                      ? 'No dev profile targets $iiOsAgentTaskWorkflow.'
                      : 'The installed dev profile does not satisfy the exact execution and credential policy.'
                : '${profile.displayName} (${profile.id}@${profile.version}) is available on dev.',
            guidance:
                'Install a profile from Agent permissions and commit it under .ii-os/agent-permissions/.',
          ),
        );
      } on ApiError catch (error) {
        checks.add(
          readinessFromGitHubError(
            id: 'permission_profile',
            label: 'Agent permission profile installed',
            repository: repository,
            error: error,
            missingCodes: const {
              'github_resource_not_found',
              'agent_permission_invalid',
            },
            guidance:
                'Install a valid profile under .ii-os/agent-permissions/ on dev.',
          ),
        );
      }
    }

    if (installerActive && sourceSha.isNotEmpty) {
      String? bootstrapTag;
      // resolveBootstrapTag already computes the exact tag, commit, and git
      // command for the missing case. Carrying them onto the check is what
      // lets the setup screen show the one action nobody else can take.
      Map<String, Object?> bootstrapDetails = const {};
      try {
        bootstrapTag = await resolveBootstrapTag(
          workspace,
          repository: repository,
        );
      } on ApiError catch (error) {
        bootstrapTag = null;
        final details = error.details;
        if (error.code == 'permission_bootstrap_tag_missing' &&
            details is Map<String, Object?>) {
          bootstrapDetails = details;
        }
      }
      checks.add(
        bootstrapTagCheck(
          repository: repository,
          tag: bootstrapTag,
          missingDetails: bootstrapDetails,
        ),
      );
    }

    if (profile == null || !installerActive) {
      checks.add(
        readinessCheck(
          id: 'permission_installer_proof',
          label: 'Permission installer is bound to current dev',
          passed: false,
          repository: repository,
          detail: !installerActive
              ? 'The v4 Fleet-backed permission installer is not active.'
              : 'No executable dev profile is available to bind to installer proof.',
          guidance:
              'Install the current workflows, then install the recommended profile again.',
        ),
      );
    } else {
      try {
        final encodedRef = Uri.encodeQueryComponent(sourceSha);
        Object? proof;
        try {
          final proofFile = _asMap(
            await _rest(
              workspace,
              'GET',
              '/repos/$repository/contents/.ii-os/agent-permission-proofs/${Uri.encodeComponent(profile.id)}.json?ref=$encodedRef',
            ),
          );
          final proofContent = proofFile['content'];
          if (proofContent is! String || proofFile['encoding'] != 'base64') {
            throw const ApiError(
              502,
              'github_response_invalid',
              'GitHub returned unreadable permission installer proof.',
            );
          }
          proof = jsonDecode(
            utf8.decode(base64Decode(proofContent.replaceAll('\n', ''))),
          );
        } on ApiError catch (error) {
          if (error.code != 'github_resource_not_found') rethrow;
        }
        final runs = await listWorkflowRuns(
          workspace,
          repository: repository,
          workflowPath:
              '.github/workflows/$iiOsAgentPermissionInstallerWorkflow',
        );
        checks.add(
          permissionInstallerProofCheck(
            runs,
            repository: repository,
            profile: profile,
            proof: proof,
            currentWorkflowBlobShas: currentWorkflowBlobShas,
            currentWorkflowModes: currentWorkflowModes,
            currentSourceSha: sourceSha,
            sourceManifest: agentTrustedSourceManifest,
          ),
        );
      } on ApiError catch (error) {
        checks.add(
          readinessUnable(
            id: 'permission_installer_proof',
            label: 'Permission installer is bound to current dev',
            repository: repository,
            error: error,
            guidance:
                'Run the current v4 Fleet-backed permission installer and wait for cleanup proof.',
          ),
        );
      } on Object {
        checks.add(
          readinessCheck(
            id: 'permission_installer_proof',
            label: 'Permission installer is bound to current dev',
            passed: false,
            repository: repository,
            detail: 'The committed permission installer proof is invalid.',
            guidance:
                'Run the current v4 Fleet-backed permission installer again.',
          ),
        );
      }
    }

    checks.addAll(agentProfileChecks(profile, repository: repository));
    if (_permissionAllows(permissions['administration'] ?? 'none', 'read')) {
      checks.add(
        await _bootstrapEnvironmentCheck(workspace, repository: repository),
      );
      if (profile != null) {
        checks.add(
          await _environmentCheck(
            workspace,
            repository: repository,
            environment: profile.runtime == null
                ? profile.secretInjection.environment
                : iiOsAgentEnvironment,
            trustedSourceRef: sourceRef,
          ),
        );
      }
    } else {
      checks.add(
        readinessCheck(
          id: 'agent_bootstrap_environment',
          label: 'Agent setup requires human approval',
          passed: false,
          repository: repository,
          detail: 'The GitHub App cannot inspect repository environments.',
          guidance:
              'Set the GitHub App Administration permission to Read-only.',
        ),
      );
      if (profile != null) {
        checks.add(
          readinessCheck(
            id: 'agent_environment',
            label: 'Protected agent environment selected',
            passed: false,
            repository: repository,
            detail: 'The GitHub App cannot inspect repository environments.',
            guidance:
                'Set the GitHub App Administration permission to Read-only.',
          ),
        );
      }
    }
    final engine = profile?.engine ?? codexAgentEngine;
    if (_permissionAllows(permissions['secrets'] ?? 'none', 'read')) {
      if (engine == codexAgentEngine) {
        checks.add(
          await _codexSecretCheck(
            workspace,
            repository: repository,
            state: codexAuthState,
          ),
        );
      }
      checks.add(
        await _agentUsageSecretCheck(workspace, repository: repository),
      );
    } else {
      if (engine == codexAgentEngine) {
        checks.add(
          readinessCheck(
            id: 'codex_auth_secret',
            label: 'Codex OAuth credential stored in GitHub',
            passed: false,
            repository: repository,
            detail: 'The GitHub App cannot verify repository secret metadata.',
            guidance:
                'Set the GitHub App Secrets permission to Read and write, then retry.',
          ),
        );
      }
      checks.add(
        readinessCheck(
          id: 'agent_usage_secret',
          label: 'Agent usage reporting key stored in GitHub',
          passed: false,
          repository: repository,
          detail: 'The GitHub App cannot verify repository secret metadata.',
          guidance:
              'Set the GitHub App Secrets permission to Read and write, then retry.',
        ),
      );
    }
    return AgentRepositoryReadinessInspection(
      sourceSha: sourceSha,
      sourceRef: sourceRef,
      engine: engine,
      checks: agentEngineUsesCodexOAuth(engine)
          ? checks
          : checks
                .where(
                  (check) => !codexAgentReadinessCheckIds.contains(check['id']),
                )
                .toList(),
    );
  }
}

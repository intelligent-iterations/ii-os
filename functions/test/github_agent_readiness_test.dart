import 'dart:convert';

import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/agent_repository_health.dart';
import 'package:ii_os_functions/src/agent_trusted_source_manifest.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_app_transport.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:ii_os_functions/src/trusted_tag_ruleset_attestation_store.dart';
import 'package:test/test.dart';

import 'support/local_agent_engine_fixture.dart';

void main() {
  test(
    'configured manifest covers every trusted executable source exactly',
    () {
      expect(_sourceManifest.configured, isTrue);
      expect(
        _sourceManifest.blobShas.keys.toSet(),
        _sourceManifest.sourcePaths.toSet(),
      );
      expect(
        _sourceManifest.blobShas.values,
        everyElement(matches(RegExp(r'^[0-9a-f]{40}$'))),
      );
      expect(
        _sourceManifest.modes.keys.toSet(),
        _sourceManifest.blobShas.keys.toSet(),
      );
      expect(
        _sourceManifest.modes.values,
        everyElement(anyOf('100644', '100755')),
      );
      final reviewedPythonPaths = _sourceManifest.blobShas.keys
          .where((path) => path.endsWith('.py'))
          .toSet();
      final namespacePythonPaths = {
        for (final directory in _sourceManifest.pythonImportNamespaces.entries)
          for (final name in directory.value) '${directory.key}/$name',
      };
      expect(reviewedPythonPaths, namespacePythonPaths);
    },
  );

  test('configured Workshop workflow retains its reviewed blob', () {
    expect(
      _sourceManifest.blobShas['.github/workflows/ii-os-agent-work-ticket.yml'],
      '4444444444444444444444444444444444444444',
    );
  });

  test('Python import namespace treats every symlink as executable input', () {
    const symlink = {
      'name': 'agent_task_cleanup',
      'type': 'blob',
      'mode': '120000',
    };
    expect(pythonImportCandidate(symlink), isTrue);
    expect(pythonImportEntryIdentity(symlink), isNot('agent_task_cleanup'));
    expect(
      pythonImportCandidate(const {'name': 'README.md', 'type': 'file'}),
      isFalse,
    );
  });

  test(
    'only separately reviewed package trees leave the sibling import set',
    () {
      const package = {'name': 'providers', 'type': 'tree', 'mode': '040000'};
      expect(pythonImportCandidate(package), isTrue);
      expect(
        pythonImportCandidate(package, reviewedDirectories: {'providers'}),
        isFalse,
      );
      for (final entry in [
        {'name': 'unreviewed', 'type': 'tree', 'mode': '040000'},
        {'name': 'providers', 'type': 'blob', 'mode': '120000'},
        {'name': 'providers', 'type': 'commit', 'mode': '160000'},
      ]) {
        expect(
          pythonImportCandidate(entry, reviewedDirectories: {'providers'}),
          isTrue,
        );
      }
    },
  );

  test('permission profiles may be read from only dev or an exact commit', () {
    expect(() => requireAgentPermissionReadRef('dev'), returnsNormally);
    expect(
      () => requireAgentPermissionReadRef(
        '0123456789abcdef0123456789abcdef01234567',
      ),
      returnsNormally,
    );
    expect(
      () => requireAgentPermissionReadRef('refs/heads/dev'),
      throwsA(isA<ApiError>()),
    );
  });

  test('trusted tag discovery accepts the complete matching-refs response', () {
    final response = List<Map<String, Object?>>.generate(387, (index) {
      final sha = index.toRadixString(16).padLeft(40, '0');
      return {
        'ref': 'refs/tags/ii-os-agent-v4-$sha',
        'object': {'type': 'commit', 'sha': sha},
      };
    });

    final tags = trustedAgentSourceTags(response);

    expect(tags, hasLength(387));
    expect(
      tags['0000000000000000000000000000000000000182'],
      'ii-os-agent-v4-0000000000000000000000000000000000000182',
    );
  });

  test('trusted tag discovery rejects an unreadable response shape', () {
    expect(
      () => trustedAgentSourceTags([
        {'ref': 'valid-shape'},
        'not-a-ref',
      ]),
      throwsA(isA<ApiError>()),
    );
  });

  test('a missing bootstrap marker ships the command that creates it', () {
    // ii-os cannot mint this marker, so the check has to hand the operator
    // everything needed to mint it elsewhere. A check that only says "not
    // done" leaves the one human-only step in the flow with no way forward.
    const sha = '4f2a9c1d3e5b7a9c1d3e5b7a9c1d3e5b7a9c1d3e';
    const tag = 'ii-os-agent-v4-bootstrap-$sha';
    final check = bootstrapTagCheck(
      repository: 'acme-co/example-app',
      tag: null,
      missingDetails: const {
        'repository': 'acme-co/example-app',
        'tag': tag,
        'sha': sha,
        'command': 'git tag $tag $sha && git push origin $tag',
      },
    );

    expect(check['status'], 'action_required');
    expect(check['requiredValue'], tag);
    expect(check['command'], 'git tag $tag $sha && git push origin $tag');
    expect(check['currentValue'], 'No marker on this commit');
  });

  test('a present bootstrap marker carries no command to run', () {
    const tag = 'ii-os-agent-v4-bootstrap-4f2a9c1';
    final check = bootstrapTagCheck(
      repository: 'acme-co/example-app',
      tag: tag,
    );

    expect(check['status'], 'passed');
    expect(check['currentValue'], tag);
    expect(check.containsKey('command'), isFalse);
  });

  test('an unexplained bootstrap failure never invents a command', () {
    // resolveBootstrapTag also throws for auth and transport failures. Those
    // carry no details, and guessing a command there would tell the operator
    // to push a tag that is not the one being looked for.
    final check = bootstrapTagCheck(
      repository: 'acme-co/example-app',
      tag: null,
    );

    expect(check['status'], 'action_required');
    expect(check.containsKey('command'), isFalse);
    expect(check.containsKey('requiredValue'), isFalse);
  });

  test('GitHub App readiness requires the permissions used by agents', () {
    final checks = githubAppPermissionChecks({
      'actions': 'write',
      'contents': 'read',
      'pull_requests': 'read',
    });
    final byId = {for (final check in checks) check['id']: check};

    expect(checks, hasLength(4));
    expect(byId['github_app_actions']?['status'], 'passed');
    expect(byId['github_app_contents']?['status'], 'action_required');
    expect(byId['github_app_contents']?['currentValue'], 'Read-only');
    expect(byId['github_app_contents']?['requiredValue'], 'Read and write');
    expect(byId['github_app_deployments']?['status'], 'warning');
    expect(byId['github_app_deployments']?['currentValue'], 'No access');
    expect(byId['github_app_deployments']?['requiredValue'], 'Read-only');
    expect(byId['github_app_pull_requests']?['status'], 'action_required');
  });

  test('Workshop readiness also requires Issues and Projects write', () {
    final checks = githubAppPermissionChecks(const {
      'actions': 'write',
      'contents': 'write',
      'deployments': 'read',
      'pull_requests': 'write',
    }, requiresWorkshop: true);
    final byId = {for (final check in checks) check['id']: check};

    expect(checks, hasLength(6));
    expect(byId['github_app_issues']?['status'], 'action_required');
    expect(
      byId['github_app_organization_projects']?['status'],
      'action_required',
    );
    expect(
      missingGitHubAppPermissions(const {
        'actions': 'write',
        'contents': 'write',
        'deployments': 'read',
        'pull_requests': 'write',
      }, requiresWorkshop: true),
      {'issues', 'organization_projects'},
    );
  });

  test('GitHub setup health does not require a runner or immutable source', () {
    final health = resolveGitHubSetupRepositoryHealth(
      repository: 'acme-co/example-app',
      checkedAt: DateTime.utc(2026, 8, 16),
      checks: [
        for (final id in const [
          'github_installation',
          'repository_selected',
          'github_repository_access',
          'github_app_actions',
          'github_app_contents',
          'github_app_deployments',
          'github_app_pull_requests',
        ])
          {
            'id': id,
            'status': id == 'github_app_deployments' ? 'warning' : 'passed',
          },
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.healthy);
    expect(health.dispatchAllowed, isTrue);
    expect(health.sourceRef, isEmpty);
  });

  test('deployment recommendation does not block agent dispatch', () {
    const sourceSha = '1111111111111111111111111111111111111111';
    final health = resolveAgentRepositoryHealth(
      repository: 'acme-co/example-app',
      checkedAt: DateTime.utc(2026, 8, 25),
      sourceSha: sourceSha,
      sourceRef: 'ii-os-agent-v4-$sourceSha',
      checks: const [
        {'id': 'github_app_actions', 'status': 'passed'},
        {'id': 'github_app_deployments', 'status': 'warning'},
      ],
    );

    expect(health.status, AgentRepositoryHealthStatus.healthy);
    expect(health.dispatchAllowed, isTrue);
    expect(health.blockers, isEmpty);
    expect(health.advisories, hasLength(1));
  });

  test('ticket dispatch omits setup ceremony from the live queue gate', () {
    final checks = agentDispatchReadinessChecks([
      {'id': 'agent_workflow', 'status': 'passed'},
      {'id': 'permission_profile', 'status': 'passed'},
      {'id': 'immutable_tag_protection', 'status': 'action_required'},
      {'id': 'trusted_agent_source_manifest', 'status': 'action_required'},
      {'id': 'permission_installer_proof', 'status': 'action_required'},
    ]);

    expect(checks.map((check) => check['id']), [
      'agent_workflow',
      'permission_profile',
    ]);
  });

  test('a readiness refresh never answers from a cached installation token', () {
    final now = DateTime.utc(2026, 8, 2, 12);
    final liveToken = now.add(const Duration(minutes: 55));

    expect(
      installationTokenReusable(expiresAt: liveToken, now: now, refresh: false),
      isTrue,
      reason: 'an ordinary call may still reuse a live token',
    );
    expect(
      installationTokenReusable(expiresAt: liveToken, now: now, refresh: true),
      isFalse,
      reason:
          'a readiness refresh must re-read the permissions GitHub grants now',
    );
    expect(
      installationTokenReusable(
        expiresAt: now.add(const Duration(minutes: 1)),
        now: now,
        refresh: false,
      ),
      isFalse,
      reason: 'a token inside the two-minute expiry margin is not reusable',
    );
    expect(
      installationTokenReusable(expiresAt: null, now: now, refresh: false),
      isFalse,
      reason: 'an empty cache always mints a token',
    );
  });

  test('a pending installation request routes to the accept page', () {
    const appHasBoth = {
      'actions': 'write',
      'contents': 'write',
      'deployments': 'read',
      'pull_requests': 'write',
    };
    const installationMissingBoth = {
      'actions': 'write',
      'contents': 'write',
      'deployments': 'read',
    };

    expect(missingGitHubAppPermissions(installationMissingBoth), {
      'pull_requests',
    });
    expect(
      githubAppPermissionEditPending(
        appPermissions: appHasBoth,
        installationPermissions: installationMissingBoth,
      ),
      isFalse,
      reason: 'the App already grants them, so only acceptance is left',
    );
    expect(
      githubAppPermissionEditPending(
        appPermissions: installationMissingBoth,
        installationPermissions: installationMissingBoth,
      ),
      isTrue,
      reason: 'the App itself still lacks them, so the App must be edited',
    );
    expect(
      githubAppPermissionEditPending(
        appPermissions: {...appHasBoth, 'pull_requests': 'read'},
        installationPermissions: installationMissingBoth,
      ),
      isTrue,
      reason: 'a too-narrow App level still needs an App edit',
    );
  });

  test('the accept page belongs to the installing account', () {
    expect(
      const GitHubInstallationIdentity(
        installationId: 12345678,
        accountLogin: 'acme-co',
        accountType: 'Organization',
      ).permissionUpdateUrl,
      'https://github.com/organizations/acme-co/settings/installations/12345678/permissions/update',
    );
    expect(
      const GitHubInstallationIdentity(
        installationId: 42,
        accountLogin: 'octocat',
        accountType: 'User',
      ).permissionUpdateUrl,
      'https://github.com/settings/installations/42/permissions/update',
    );
  });

  test('GitHub App identity links directly to permission settings', () {
    expect(
      const GitHubAppIdentity(
        slug: 'workspace-app',
        ownerLogin: 'acme-co',
        ownerType: 'Organization',
      ).permissionSettingsUrl,
      'https://github.com/organizations/acme-co/settings/apps/workspace-app/permissions',
    );
    expect(
      const GitHubAppIdentity(
        slug: 'personal-app',
        ownerLogin: 'octocat',
        ownerType: 'User',
      ).permissionSettingsUrl,
      'https://github.com/settings/apps/personal-app/permissions',
    );
  });

  test(
    'agent profile readiness proves runtime and required secret bindings',
    () {
      final checks = agentProfileChecks(
        AgentPermissionProfile.parse(_completeProfile),
        repository: 'acme-co/example-app',
      );

      expect(checks, hasLength(3));
      expect(checks.every((check) => check['status'] == 'passed'), isTrue);
      expect(
        checks.singleWhere(
          (check) => check['id'] == 'codex_secret_binding',
        )['detail'],
        contains('CODEX_AUTH_JSON_FILE'),
      );
      expect(
        checks.singleWhere(
          (check) => check['id'] == 'agent_usage_secret_binding',
        )['detail'],
        contains('AGENT_USAGE_KEY_FILE'),
      );
    },
  );

  test('local Qwen readiness has no Codex workflow or secret prerequisite', () {
    final engines = exampleLocalEngines();
    final profile = AgentPermissionProfile.parse(
      exampleLocalQwenProfile(_completeProfile),
      engines: engines,
    );
    final checks = agentProfileChecks(
      profile,
      repository: 'acme-co/example-app',
      engines: engines,
    );

    expect(
      checks.map((check) => check['id']),
      isNot(contains('codex_secret_binding')),
    );
    expect(checks, hasLength(2));
    expect(checks.every((check) => check['status'] == 'passed'), isTrue);
    expect(
      agentDispatchReadinessChecks([
        ...checks,
        {'id': 'codex_auth_secret', 'status': 'action_required'},
      ], engine: profile.engine).map((check) => check['id']),
      isNot(contains('codex_auth_secret')),
    );
  });

  test('profile listings name the local engine this deployment offers', () {
    final listing = {
      ...exampleLocalQwenProfile(_completeProfile),
      'repository': 'acme-co/example-app',
      'ref': 'dev',
      'path': '.ii-os/agent-permissions/qwen38-repository-maintainer.json',
      'sha': 'a' * 40,
    };

    expect(
      () => executableAgentPermissionProfileFromListings([
        listing,
      ], 'qwen38-repository-maintainer'),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'agent_engine_not_configured',
        ),
      ),
    );
    expect(
      executableAgentPermissionProfileFromListings(
        [listing],
        'qwen38-repository-maintainer',
        engines: exampleLocalEngines(),
      )?.engine,
      qwen38LocalAgentEngine,
    );
  });

  test('profile listing metadata is not parsed as permission schema', () {
    final listing = {
      ..._completeProfile,
      'repository': 'acme-co/example-app',
      'ref': 'dev',
      'path': '.ii-os/agent-permissions/repository-maintainer.json',
      'sha': 'a' * 40,
    };
    final profile = agentPermissionProfileFromListing(listing);

    expect(profile.id, 'repository-maintainer');
    expect(profile.workflow.file, iiOsAgentTaskWorkflow);
    expect(
      executableAgentPermissionProfileFromListings([
        listing,
      ], 'repository-maintainer'),
      isNotNull,
    );
    expect(
      executableAgentPermissionProfileFromListings([
        listing,
      ], 'missing-profile'),
      isNull,
    );
  });

  test('agent profile readiness blocks a missing executable profile', () {
    final checks = agentProfileChecks(null, repository: 'acme-co/example-app');
    final capabilities = checks.singleWhere(
      (check) => check['id'] == 'fleet_capabilities',
    );

    expect(capabilities['status'], 'action_required');
    expect(capabilities['detail'], contains('Install a profile'));
  });

  test('GitHub 404 is missing while an upstream error is unverifiable', () {
    final missing = readinessFromGitHubError(
      id: 'codex_auth_secret',
      label: 'Codex secret',
      repository: 'acme-co/example-app',
      error: const ApiError(404, 'github_resource_not_found', 'Not found.'),
      missingCodes: const {'github_resource_not_found'},
      guidance: 'Add it.',
    );
    final unavailable = readinessFromGitHubError(
      id: 'codex_auth_secret',
      label: 'Codex secret',
      repository: 'acme-co/example-app',
      error: const ApiError(502, 'github_request_failed', 'GitHub failed.'),
      missingCodes: const {'github_resource_not_found'},
      guidance: 'Retry.',
    );

    expect(missing['status'], 'action_required');
    expect(unavailable['status'], 'unable_to_verify');
  });

  test(
    'repository readiness requires work and Codex verification workflows',
    () {
      final checks = repositoryWorkflowChecks([
        {'path': '.github/workflows/ii-os-agent-task.yml', 'state': 'active'},
        {'path': '.github/workflows/ii-os-codex-auth.yml', 'state': 'active'},
        {
          'path': '.github/workflows/ii-os-codex-auth-finalize.yml',
          'state': 'active',
        },
      ], repository: 'acme-co/example-app');
      final byId = {for (final check in checks) check['id']: check};

      expect(checks, hasLength(4));
      expect(
        checks
            .where((check) => check['id'] == 'permission_installer_workflow')
            .single['status'],
        'action_required',
      );
      expect(byId['agent_workflow']?['status'], 'passed');
      expect(byId['codex_auth_workflow']?['status'], 'passed');
      expect(byId['codex_auth_finalize_workflow']?['status'], 'passed');
    },
  );

  test('agent gateway and reusable job bind credentials after cleanup', () {
    const workTicketSource = '''
jobs:
  dispatch:
    permissions:
      contents: read
      id-token: write
    runs-on: [self-hosted, example-runner]
    environment: ii-os-agent-maintainer
    steps:
      - id: api-token
        uses: actions/create-github-app-token@0123456789012345678901234567890123456789
        with:
          permission-contents: read
          permission-issues: read
          permission-pull-requests: read
      - id: token-stage
        env:
          API_TOKEN: read
        run: echo stage
      - id: fleet
        env:
          GITHUB_API_TOKEN: read
        run: echo fleet
      - name: Remove staged token files
        id: token-cleanup
        run: echo cleanup
      - name: Authorize exact branch publication after cleanup
        id: publication-authorization
        run: |
          response="\$(curl /authorize-publication)"
          publication_token="\$(jq -er '.data.publicationToken' <<< "\$response")"
          publication_app_login="\$(jq -er '.data.publicationAppLogin' <<< "\$response")"
          echo "::add-mask::\$publication_token"
      - id: post-read-token
        uses: actions/create-github-app-token@0123456789012345678901234567890123456789
        with:
          permission-contents: read
      - name: Publish the authorized exact change bundle
        id: publication
        env:
          GITHUB_PUSH_TOKEN: \${{ steps.publication-authorization.outputs.publication_token }}
          PUSH_APP_LOGIN: \${{ steps.publication-authorization.outputs.publication_app_login }}
        run: echo publish
      - name: Finalize the exact ticket through the ii-os broker
        if: steps.token-cleanup.outputs.proven == 'true' && steps.fleet.outputs.fleet_cleanup_proven == 'true'
        env:
          AGENT_BUNDLE_ARTIFACT_B64: \${{ steps.fleet.outputs.agent_bundle_artifact_b64 }}
          FLEET_STEP_OUTCOME: \${{ steps.fleet.outcome }}
          PUBLISH_STEP_OUTCOME: \${{ steps.publication.outcome }}
        run: |
          if [[ "\$FLEET_STEP_OUTCOME" == 'success' &&
                -n "\$AGENT_RESULT_B64" &&
                ( -z "\$AGENT_BUNDLE_ARTIFACT_B64" ||
                  "\$PUBLISH_STEP_OUTCOME" == 'success' ) ]]; then
            echo use-result
          else
            echo 'pull_request: null'
          fi
          curl /finalize
  other:
    runs-on: [self-hosted, example-runner]
''';
    const gatewaySource = '''
permissions: {}
jobs:
  work-ticket:
    if: \${{ inputs.operation == 'work_ticket' }}
    permissions:
      contents: read
      id-token: write
    uses: ./.github/workflows/ii-os-agent-work-ticket.yml
    with:
      operation: work_ticket
      repository: \${{ inputs.repository }}
      issue_number: \${{ inputs.issue_number }}
      permission_profile: \${{ inputs.permission_profile }}
      permission_ref: \${{ inputs.permission_ref }}
      project_item_id: \${{ inputs.project_item_id }}
      permission_digest: \${{ inputs.permission_digest }}
      dispatch_id: \${{ inputs.dispatch_id }}
      workspace_id: \${{ inputs.workspace_id }}
      codex_secret_digest: \${{ inputs.codex_secret_digest }}
      trusted_source_sha: \${{ inputs.trusted_source_sha }}
      auth_smoke: \${{ inputs.auth_smoke }}
      coordinator_source_sha: \${{ inputs.coordinator_source_sha || github.sha }}
    secrets: inherit
''';
    final passed = agentWorkflowEnvironmentCheck(
      gatewaySource,
      workTicketSource: workTicketSource,
      repository: 'acme-co/example-app',
    );
    final missing = agentWorkflowEnvironmentCheck('''
jobs:
  dispatch:
    runs-on: [self-hosted, example-runner]
    steps: []
''', repository: 'acme-co/example-app');

    expect(passed['status'], 'passed');
    expect(missing['status'], 'action_required');
    expect(
      agentWorkflowEnvironmentCheck(
        gatewaySource.replaceFirst(
          r'${{ inputs.permission_digest }}',
          r'${{ inputs.dispatch_id }}',
        ),
        workTicketSource: workTicketSource,
        repository: 'acme-co/example-app',
      )['status'],
      'action_required',
    );
  });

  test('permission health binds latest v4 proof to all executable sources', () {
    final profile = AgentPermissionProfile.parse(_completeProfile);
    final digest = agentPermissionProfileDigest(profile);
    final now = DateTime.utc(2026, 7, 27, 16);
    const sourceSha = '1111111111111111111111111111111111111111';
    final trustedSourceShas = {
      for (final path in _sourceManifest.sourcePaths)
        path: '2222222222222222222222222222222222222222',
    };
    final trustedSourceModes = {
      for (final path in _sourceManifest.sourcePaths)
        path: _sourceManifest.modes[path]!,
    };
    final namespaceShas = {
      for (final path in _sourceManifest.sourcePaths)
        if (path.startsWith('.github/workflows/'))
          path: '2222222222222222222222222222222222222222',
    };
    final namespaceModes = {
      for (final path in namespaceShas.keys) path: '100644',
    };
    final proof = {
      'schema_version': 1,
      'security_contract': iiOsAgentSecurityContract,
      'approval_id': 'apv-example',
      'dispatch_id': 'd' * 24,
      'profile_id': profile.id,
      'profile_version': profile.version,
      'profile_digest': digest,
      'installer_run_id': 800,
      'installer_run_attempt': 1,
      'installer_source_sha': sourceSha,
      'trusted_source_blob_shas': trustedSourceShas,
      'trusted_source_modes': trustedSourceModes,
      'workflow_namespace_blob_shas': namespaceShas,
      'workflow_namespace_modes': namespaceModes,
      'runtime_image': profile.fleet.image,
    };
    final check = permissionInstallerProofCheck(
      [
        {
          'run_number': 8,
          'id': 800,
          'run_attempt': 1,
          'display_title':
              'ii-os permission v4 / apv-example / ${'d' * 24} / '
              '${profile.id}@${profile.version} / $digest / '
              'bootstrap@$sourceSha',
          'event': 'workflow_dispatch',
          'head_branch': 'ii-os-agent-v4-bootstrap-$sourceSha',
          'head_sha': sourceSha,
          'path': '.github/workflows/ii-os-agent-permissions.yml',
          'status': 'completed',
          'conclusion': 'success',
          'html_url': 'https://github.com/acme-co/example-app/actions/runs/800',
          'created_at': now
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
        },
      ],
      repository: 'acme-co/example-app',
      profile: profile,
      proof: proof,
      currentWorkflowBlobShas: trustedSourceShas,
      currentWorkflowModes: trustedSourceModes,
      currentSourceSha: sourceSha,
      sourceManifest: _sourceManifest,
      clock: () => now,
    );
    final changedWorkflow = permissionInstallerProofCheck(
      [
        {
          'run_number': 8,
          'id': 800,
          'run_attempt': 1,
          'display_title':
              'ii-os permission v4 / apv-example / ${'d' * 24} / '
              '${profile.id}@${profile.version} / $digest / '
              'bootstrap@$sourceSha',
          'event': 'workflow_dispatch',
          'head_branch': 'ii-os-agent-v4-bootstrap-$sourceSha',
          'head_sha': sourceSha,
          'path': '.github/workflows/ii-os-agent-permissions.yml',
          'status': 'completed',
          'conclusion': 'success',
          'created_at': now
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
        },
      ],
      repository: 'acme-co/example-app',
      profile: profile,
      proof: proof,
      currentWorkflowBlobShas: {
        ...trustedSourceShas,
        '.github/workflows/ii-os-agent-task.yml':
            '6666666666666666666666666666666666666666',
      },
      currentWorkflowModes: trustedSourceModes,
      currentSourceSha: sourceSha,
      sourceManifest: _sourceManifest,
      clock: () => now,
    );

    expect(check['status'], 'passed');
    expect(check['runStatus'], 'succeeded');
    expect(
      check['runUrl'],
      'https://github.com/acme-co/example-app/actions/runs/800',
    );
    expect(changedWorkflow['status'], 'action_required');
    expect(changedWorkflow['runStatus'], 'verification_failed');
  });

  test('failed permission install is explicit without a committed proof', () {
    final profile = AgentPermissionProfile.parse(_completeProfile);
    final digest = agentPermissionProfileDigest(profile);
    const sourceSha = '1111111111111111111111111111111111111111';
    final check = permissionInstallerProofCheck(
      [
        {
          'run_number': 9,
          'id': 801,
          'run_attempt': 1,
          'display_title':
              'ii-os permission v4 / apv-example / ${'e' * 24} / '
              '${profile.id}@${profile.version} / $digest / '
              'bootstrap@$sourceSha',
          'event': 'workflow_dispatch',
          'head_branch': 'ii-os-agent-v4-bootstrap-$sourceSha',
          'head_sha': sourceSha,
          'path': '.github/workflows/ii-os-agent-permissions.yml',
          'status': 'completed',
          'conclusion': 'failure',
          'html_url': 'https://github.com/acme-co/example-app/actions/runs/801',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      repository: 'acme-co/example-app',
      profile: profile,
      proof: null,
      currentWorkflowBlobShas: const {},
      currentWorkflowModes: const {},
      currentSourceSha: sourceSha,
      sourceManifest: _sourceManifest,
    );

    expect(check['status'], 'action_required');
    expect(check['runStatus'], 'failed');
    expect(check['runUrl'], contains('/actions/runs/801'));
    expect(check['detail'], contains('completed with failure'));
  });

  test(
    'successful run without durable proof names the publication failure',
    () {
      final profile = AgentPermissionProfile.parse(_completeProfile);
      final digest = agentPermissionProfileDigest(profile);
      const sourceSha = '1111111111111111111111111111111111111111';
      final check = permissionInstallerProofCheck(
        [
          {
            'run_number': 10,
            'id': 802,
            'run_attempt': 1,
            'display_title':
                'ii-os permission v4 / apv-example / ${'f' * 24} / '
                '${profile.id}@${profile.version} / $digest / '
                'bootstrap@$sourceSha',
            'event': 'workflow_dispatch',
            'head_branch': 'ii-os-agent-v4-bootstrap-$sourceSha',
            'head_sha': sourceSha,
            'path': '.github/workflows/ii-os-agent-permissions.yml',
            'status': 'completed',
            'conclusion': 'success',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        repository: 'acme-co/example-app',
        profile: profile,
        proof: null,
        currentWorkflowBlobShas: const {},
        currentWorkflowModes: const {},
        currentSourceSha: sourceSha,
        sourceManifest: _sourceManifest,
      );

      expect(check['runStatus'], 'verification_failed');
      expect(check['detail'], contains('does not contain'));
      expect(check['detail'], contains('durable installation proof'));
    },
  );

  test('environment and secret checks require exact live attestations', () {
    expect(
      githubRuntimeEnvironmentProtected(
        {
          'can_admins_bypass': false,
          'protection_rules': [
            {'type': 'branch_policy'},
          ],
          'deployment_branch_policy': {
            'protected_branches': false,
            'custom_branch_policies': true,
          },
        },
        [
          {'type': 'tag', 'name': 'ii-os-agent-v4-${'a' * 40}'},
        ],
        'ii-os-agent-v4-${'a' * 40}',
      ),
      isTrue,
    );
    expect(
      githubRuntimeEnvironmentProtected(
        {
          'can_admins_bypass': false,
          'protection_rules': [
            {'type': 'branch_policy'},
          ],
          'deployment_branch_policy': {
            'protected_branches': false,
            'custom_branch_policies': true,
          },
        },
        [
          {'type': 'tag', 'name': 'ii-os-agent-v4-*'},
        ],
        'ii-os-agent-v4-${'a' * 40}',
      ),
      isFalse,
    );
    expect(
      githubBootstrapEnvironmentProtected(
        {
          'can_admins_bypass': false,
          'protection_rules': [
            {'type': 'branch_policy'},
          ],
          'deployment_branch_policy': {
            'protected_branches': false,
            'custom_branch_policies': true,
          },
        },
        [
          {'type': 'tag', 'name': 'ii-os-agent-v4-bootstrap-*'},
        ],
      ),
      isTrue,
    );
    expect(
      githubBootstrapEnvironmentProtected(
        {
          'can_admins_bypass': false,
          'protection_rules': [
            {'type': 'branch_policy'},
            {
              'type': 'required_reviewers',
              'reviewers': [
                {'type': 'User'},
              ],
            },
          ],
          'deployment_branch_policy': {
            'protected_branches': false,
            'custom_branch_policies': true,
          },
        },
        [
          {'type': 'branch', 'name': 'dev'},
        ],
      ),
      isFalse,
    );
    expect(
      githubTrustedTagRulesetProtected([
        {
          'target': 'tag',
          'enforcement': 'active',
          'bypass_actors': <Object?>[],
          'conditions': {
            'ref_name': {
              'include': ['refs/tags/ii-os-agent-v4-*'],
              'exclude': <Object?>[],
            },
          },
          'rules': [
            {'type': 'update'},
            {'type': 'deletion'},
          ],
        },
      ]),
      isTrue,
    );
    expect(
      githubTrustedTagRulesetProtected([
        {
          'target': 'tag',
          'enforcement': 'active',
          'bypass_actors': [
            {'actor_type': 'OrganizationAdmin'},
          ],
          'conditions': {
            'ref_name': {
              'include': ['refs/tags/ii-os-agent-v4-*'],
              'exclude': <Object?>[],
            },
          },
          'rules': [
            {'type': 'update'},
            {'type': 'deletion'},
          ],
        },
      ]),
      isFalse,
    );
    final hiddenBypass = [
      {
        'target': 'tag',
        'enforcement': 'active',
        'current_user_can_bypass': 'never',
        'conditions': {
          'ref_name': {
            'include': ['refs/tags/ii-os-agent-v4-*'],
            'exclude': <Object?>[],
          },
        },
        'rules': [
          {'type': 'update'},
          {'type': 'deletion'},
        ],
      },
    ];
    expect(githubTrustedTagRulesetProtected(hiddenBypass), isFalse);
    expect(githubTrustedTagRulesetBypassHidden(hiddenBypass), isTrue);
    expect(
      githubTrustedTagRulesetProtected(
        jsonDecode('''
          [{
            "target":"tag",
            "enforcement":"active",
            "bypass_actors":[],
            "conditions":{"ref_name":{
              "include":["refs/tags/ii-os-agent-v4-*"],
              "exclude":[]
            }},
            "rules":[{"type":"update"},{"type":"deletion"}]
          }]
        ''')
            as List<Object?>,
      ),
      isTrue,
      reason: 'GitHub responses arrive as decoded runtime maps and lists',
    );
    expect(
      codexSecretMetadataMatches(
        '2026-07-27T16:00:00Z',
        '2026-07-27T16:00:00.000Z',
      ),
      isTrue,
    );
    expect(
      codexSecretMetadataMatches(
        '2026-07-27T16:00:01Z',
        '2026-07-27T16:00:00Z',
      ),
      isFalse,
    );
  });

  test('a no-bypass attestation expires on any ruleset version change', () {
    final attestation = TrustedTagRulesetAttestation(
      repository: 'acme-co/example-app',
      installationId: 123,
      rulesetId: 42,
      rulesetUpdatedAt: '2026-08-13T12:00:00Z',
      rulesetSource: 'acme-co/example-app',
      rulesetSourceType: 'Repository',
      attestedBy: 'trusted-admin',
      attestedAt: DateTime.utc(2026, 8, 13, 12, 1),
    );
    final ruleset = <String, Object?>{
      'id': 42,
      'updated_at': '2026-08-13T12:00:00Z',
      'source': 'acme-co/example-app',
      'source_type': 'Repository',
    };

    expect(
      attestation.matches(
        currentRepository: 'acme-co/example-app',
        currentInstallationId: 123,
        ruleset: ruleset,
      ),
      isTrue,
    );
    expect(
      attestation.matches(
        currentRepository: 'acme-co/example-app',
        currentInstallationId: 123,
        ruleset: {...ruleset, 'updated_at': '2026-08-13T12:05:00Z'},
      ),
      isFalse,
    );
    expect(
      attestation.matches(
        currentRepository: 'acme-co/example-app',
        currentInstallationId: 124,
        ruleset: ruleset,
      ),
      isFalse,
    );
    expect(
      trustedTagRulesetSnapshotMatches(
        ruleset: ruleset,
        expectedRulesetId: 42,
        expectedRulesetUpdatedAt: '2026-08-13T12:00:00Z',
      ),
      isTrue,
    );
    expect(
      trustedTagRulesetSnapshotMatches(
        ruleset: ruleset,
        expectedRulesetId: 42,
        expectedRulesetUpdatedAt: '2026-08-13T12:05:00Z',
      ),
      isFalse,
    );
  });

  test('trusted source manifest rejects added or changed executable blobs', () {
    final exact = trustedAgentSourceManifestCheck(
      const {'workflow': '1'},
      const {'workflow': '1'},
      repository: 'acme-co/example-app',
    );
    final changed = trustedAgentSourceManifestCheck(
      const {'workflow': '2'},
      const {'workflow': '1'},
      repository: 'acme-co/example-app',
    );
    final added = trustedAgentSourceManifestCheck(
      const {'workflow': '1', 'extra': '2'},
      const {'workflow': '1'},
      repository: 'acme-co/example-app',
    );
    final symlinked = trustedAgentSourceManifestCheck(
      const {'workflow': '1'},
      const {'workflow': '1'},
      repository: 'acme-co/example-app',
      actualModes: const {'workflow': '120000'},
      expectedModes: const {'workflow': '100644'},
    );

    expect(exact['status'], 'passed');
    expect(changed['status'], 'action_required');
    expect(changed['detail'], contains('workflow'));
    expect(changed['guidance'], contains('Running the installer again cannot'));
    expect(added['status'], 'action_required');
    expect(added['detail'], contains('extra'));
    expect(symlinked['status'], 'action_required');
    expect(symlinked['detail'], contains('workflow'));
  });

  test('trusted Python namespace rejects import shadowing', () {
    final exact = {
      for (final entry in _sourceManifest.pythonImportNamespaces.entries)
        entry.key: {...entry.value},
    };
    final shadowed = {
      for (final entry in _sourceManifest.pythonImportNamespaces.entries)
        entry.key: {...entry.value},
    };
    shadowed['automation/helpers']!.add('hashlib.py');

    expect(
      trustedPythonImportNamespaceCheck(
        exact,
        repository: 'acme-co/example-app',
        expected: _sourceManifest.pythonImportNamespaces,
      )['status'],
      'passed',
    );
    expect(
      trustedPythonImportNamespaceCheck(
        shadowed,
        repository: 'acme-co/example-app',
        expected: _sourceManifest.pythonImportNamespaces,
      )['status'],
      'action_required',
    );
  });
}

final _sourceManifest = AgentTrustedSourceManifest.fromBase64(
  base64Encode(
    utf8.encode(
      jsonEncode({
        'schema_version': 1,
        'blob_shas': {
          '.github/workflows/ii-os-agent-permissions.yml': '1' * 40,
          '.github/workflows/ii-os-agent-permissions-impl.yml': '2' * 40,
          '.github/workflows/ii-os-agent-task.yml': '3' * 40,
          '.github/workflows/ii-os-agent-work-ticket.yml': '4' * 40,
          '.github/workflows/ii-os-codex-auth.yml': '5' * 40,
          '.github/workflows/ii-os-codex-auth-finalize.yml': '6' * 40,
          'automation/helpers/worker.py': '7' * 40,
          'automation/run.sh': '8' * 40,
        },
        'executable_paths': ['automation/run.sh'],
        'python_import_namespaces': {
          'automation/helpers': ['worker.py'],
        },
      }),
    ),
  ),
);

const _completeProfile = <String, Object?>{
  'schema_version': 1,
  'id': 'repository-maintainer',
  'version': '2026-07-18.1',
  'display_name': 'Repository maintainer',
  'description': 'Maintains a selected repository.',
  'allowed_actions': ['Edit code'],
  'denied_actions': ['Create tickets'],
  'fleet': {
    'profile': 'ii-os-agent',
    'image':
        'coder@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'runtime_kind': 'docker',
    'resources': {'ram_mb': 4096, 'cpu': 2, 'disk_gb': 40, 'timeout_s': 3600},
    'capabilities': [
      'runtime-docker',
      'auto-agent',
      'github-app-token',
      'codex-oauth',
      'codex-sandbox',
      'agent-usage-reporting',
      'linux-amd64',
    ],
  },
  'secret_injection': {
    'environment': 'ii-os-agent-maintainer',
    'bindings': [
      {
        'id': 'github-app-token',
        'capability': 'github-app-token',
        'github_secret': 'IIAUTO_GITHUB_TOKEN',
        'target': 'file',
        'target_name': 'GITHUB_TOKEN_FILE',
      },
      {
        'id': 'codex-auth',
        'capability': 'codex-oauth',
        'github_secret': 'CODEX_AUTH_JSON',
        'target': 'file',
        'target_name': 'CODEX_AUTH_JSON_FILE',
      },
      {
        'id': 'agent-usage',
        'capability': 'agent-usage-reporting',
        'github_secret': 'II_OS_AGENT_USAGE_API_KEY',
        'target': 'file',
        'target_name': 'AGENT_USAGE_KEY_FILE',
      },
    ],
  },
  'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
};

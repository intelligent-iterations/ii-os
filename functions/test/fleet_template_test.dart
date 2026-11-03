import 'dart:convert';

import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/fleet_template.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

void main() {
  test('accepts and builds a versioned direct-command template', () {
    final catalog = FleetTemplateCatalog.parse(_catalog(enabled: true));
    final built = catalog.build(
      workspace: const Workspace(
        id: 'workspace-1',
        name: 'Workspace',
        environment: 'dev',
        githubInstallationId: null,
        repositories: [],
        projects: [],
        workflows: [],
        artifactStorage: null,
      ),
      actorUid: 'user-1',
      requestId: 'request-1',
      kind: 'image_create',
      input: {'prompt': 'A precise product image', 'aspectRatio': '1:1'},
    );

    expect(built.templateVersion, '2026-07-11.1');
    expect(built.model, 'Image Create');
    expect(built.request['image'], 'registry.example/media:2026-07-11');
    final runner = built.request['runner']! as Map<String, Object?>;
    final registration = runner['registration']! as Map<String, Object?>;
    expect(registration['command'], '/opt/jobs/image-create');
    expect(
      registration['artifact_prefix'],
      'workspaces/workspace-1/runs/request-1',
    );
    expect(jsonDecode(registration['artifact_paths_json']! as String), [
      'artifacts/image.png',
    ]);
  });

  test('freezes an explicit workspace runner grant into Fleet placement', () {
    final catalog = FleetTemplateCatalog.parse(_catalog(enabled: true));
    final resources = OrganizationResourceCatalog.fromOrganizationData(
      'organization-1',
      {
        'resourceCatalogVersion': organizationResourceCatalogVersion,
        'gcpResources': const <Object?>[],
        'githubResources': const <Object?>[],
        'runnerPools': [
          {
            'id': 'runner_personal',
            'name': 'Alice host',
            'provider': 'fleet',
            'providerPoolId': 'personal-alice',
            'capabilities': ['runtime-docker', 'image-generation'],
            'maxCpu': 8,
            'maxRamMiB': 16384,
            'maxConcurrent': 1,
            'active': true,
          },
        ],
      },
      emulated: true,
    );
    final built = catalog.build(
      workspace: Workspace(
        id: 'workspace-1',
        name: 'Workspace',
        environment: 'dev',
        githubInstallationId: null,
        repositories: const [],
        projects: const [],
        workflows: const [],
        artifactStorage: null,
        organizationResources: resources,
        resourceGrants: const WorkspaceResourceGrants(
          gcp: [],
          github: [],
          runners: [
            WorkspaceRunnerGrant(
              resourceId: 'runner_personal',
              capabilities: {'runtime-docker', 'image-generation'},
              maxCpu: 4,
              maxRamMiB: 8192,
              maxConcurrent: 1,
              primary: true,
            ),
          ],
        ),
        resourceGrantsExplicit: true,
      ),
      actorUid: 'user-1',
      requestId: 'request-1',
      kind: 'image_create',
      input: {'prompt': 'A precise product image', 'aspectRatio': '1:1'},
    );

    expect(built.request['pool'], 'personal-alice');
    final tags = built.request['tags']! as Map<String, Object?>;
    expect(tags['runner_resource_id'], 'runner_personal');
  });

  test('disabled templates fail closed before a request is queued', () {
    final catalog = FleetTemplateCatalog.parse(_catalog(enabled: false));
    expect(
      () => catalog.build(
        workspace: const Workspace(
          id: 'workspace-1',
          name: 'Workspace',
          environment: 'dev',
          githubInstallationId: null,
          repositories: [],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        actorUid: 'user-1',
        requestId: 'request-1',
        kind: 'image_create',
        input: {'prompt': 'image'},
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'job_template_disabled',
        ),
      ),
    );
  });

  test('rejects artifact declarations outside the artifact directory', () {
    final decoded = jsonDecode(_catalog(enabled: true)) as Map<String, Object?>;
    final templates = decoded['templates']! as Map<String, Object?>;
    final template = templates['image_create']! as Map<String, Object?>;
    final execution = template['execution']! as Map<String, Object?>;
    execution['artifact_paths'] = ['job.json'];
    expect(
      () => FleetTemplateCatalog.parse(jsonEncode(decoded)),
      throwsA(isA<ApiError>()),
    );
  });
}

String _catalog({required bool enabled}) => jsonEncode({
  'schema_version': 1,
  'templates': {
    'image_create': {
      'version': '2026-07-11.1',
      'display_name': 'Image Create',
      'enabled': enabled,
      'disabled_reason': 'Not proven yet.',
      'execution': {
        'profile': 'media',
        'image': 'registry.example/media:2026-07-11',
        'runtime_kind': 'docker',
        'resources': {
          'ram_mb': 8192,
          'cpu': 4,
          'disk_gb': 40,
          'timeout_s': 1800,
        },
        'capabilities': ['runtime-docker', 'image-generation'],
        'command': '/opt/jobs/image-create',
        'cwd': '/workspace',
        'input_flags': {
          'prompt': '--prompt',
          'width': '--width',
          'height': '--height',
        },
        'artifact_paths': ['artifacts/image.png'],
        'max_log_bytes': 1048576,
      },
    },
  },
});

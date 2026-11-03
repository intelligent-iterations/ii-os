import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/github_workflow_coordinator.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

void main() {
  group('editor render capability', () {
    test('provider discovery cache expires at its explicit TTL', () {
      var now = DateTime.utc(2026, 8, 24, 17);
      final cache = ConnectedWorkflowDiscoveryCache(
        ttl: const Duration(minutes: 1),
        clock: () => now,
      );
      cache.write(
        'workspace-1',
        const ConnectedWorkflowDiscoveryResult(
          workflowKey: 'example/media#video-editor-render',
          failed: false,
        ),
      );

      expect(cache.read('workspace-1')?.workflowKey, isNotNull);
      now = now.add(const Duration(minutes: 1));
      expect(cache.read('workspace-1'), isNull);
    });

    test('legacy workspaces use an active connected workflow', () {
      final result = evaluateEditorRenderCapability(
        workspace: _workspace(),
        workflowKey: 'example/media#video-editor-render',
      );

      expect(result.status, ConnectedWorkflowStatus.available);
      expect(result.toJson(), {
        'status': 'available',
        'requiredCapabilities': ['ffmpeg-client-validation', 'runtime-docker'],
        'minimumCpu': 4,
        'minimumRamMiB': 8192,
      });
    });

    test('explicit workspaces fail closed without a capable runner grant', () {
      final result = evaluateEditorRenderCapability(
        workspace: _workspace(
          explicit: true,
          runnerCapabilities: const {'runtime-docker'},
        ),
        workflowKey: 'example/media#video-editor-render',
      );

      expect(result.status, ConnectedWorkflowStatus.unavailable);
      expect(result.workflowKey, isNull);
    });

    test('explicit workspaces expose a fully bounded compatible runner', () {
      final result = evaluateEditorRenderCapability(
        workspace: _workspace(
          explicit: true,
          runnerCapabilities: const {
            'runtime-docker',
            'ffmpeg-client-validation',
          },
        ),
        workflowKey: 'example/media#video-editor-render',
      );

      expect(result.status, ConnectedWorkflowStatus.available);
      expect(result.workflowKey, 'example/media#video-editor-render');
    });

    test('provider errors remain unknown instead of claiming no runner', () {
      final result = evaluateEditorRenderCapability(
        workspace: _workspace(),
        discoveryFailed: true,
      );

      expect(result.status, ConnectedWorkflowStatus.unknown);
    });
  });
}

Workspace _workspace({
  bool explicit = false,
  Set<String> runnerCapabilities = const {},
}) {
  final pool = OrganizationRunnerPool(
    id: 'runner-1',
    name: 'Workspace runners',
    provider: 'customer',
    capabilities: runnerCapabilities,
    maxCpu: 8,
    maxRamMiB: 16384,
    maxConcurrent: 2,
  );
  return Workspace(
    id: 'workspace-1',
    name: 'Example',
    environment: 'dev',
    githubInstallationId: 7,
    repositories: const ['example/media'],
    projects: const [],
    workflows: const [],
    artifactStorage: null,
    organizationResources: explicit
        ? OrganizationResourceCatalog(
            gcpResources: const [],
            githubResources: const [],
            runnerPools: [pool],
          )
        : const OrganizationResourceCatalog.empty(),
    resourceGrants: explicit
        ? WorkspaceResourceGrants(
            gcp: const [],
            github: const [],
            runners: [
              WorkspaceRunnerGrant(
                resourceId: pool.id,
                capabilities: runnerCapabilities,
                maxCpu: 4,
                maxRamMiB: 8192,
                maxConcurrent: 1,
                primary: true,
              ),
            ],
          )
        : const WorkspaceResourceGrants.empty(),
    resourceGrantsExplicit: explicit,
  );
}

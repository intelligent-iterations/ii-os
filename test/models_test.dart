import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/models/models.dart';

void main() {
  test('parses workspace-specific roles and capabilities', () {
    final session = SessionModel.fromJson({
      'user': {
        'uid': 'user-1',
        'email': 'editor@example.com',
        'displayName': 'Editor',
        'isOwner': false,
      },
      'workspaces': [
        {
          'workspace': {
            'id': 'workspace-1',
            'name': 'Studio',
            'environment': 'dev',
            'repositories': ['acme/media'],
            'projects': <Object?>[],
            'workflows': <Object?>[],
            'connection': {
              'schemaVersion': 2,
              'workspaceId': '123e4567-e89b-42d3-a456-426614174000',
              'projectId': 'customer-project',
              'bucket': 'customer-media',
            },
          },
          'membership': {
            'workspaceId': 'workspace-1',
            'uid': 'user-1',
            'email': 'editor@example.com',
            'role': 'editor',
            'roleLabel': 'Editor',
            'featureClaims': ['jobs.trigger'],
            'effectiveCapabilities': ['workspace.read', 'jobs.trigger'],
          },
        },
      ],
    });

    expect(session.workspaces.single.workspace.name, 'Studio');
    expect(
      session.workspaces.single.workspace.connection?.bucket,
      'customer-media',
    );
    expect(session.workspaces.single.membership.can('jobs.trigger'), isTrue);
    expect(session.workspaces.single.membership.can('members.manage'), isFalse);
  });

  test('reads a persisted workspace data-plane connection', () {
    final connection = DataPlaneConnectionModel.fromJson({
      'schemaVersion': 2,
      'workspaceId': '123e4567-e89b-42d3-a456-426614174000',
      'projectId': 'customer-media-123',
      'projectNumber': '123456789012',
      'databaseId': 'ii-os-data',
      'region': 'us-central1',
      'bucket': 'customer-media-assets',
      'dataServiceAccount': 'broker@example-platform.iam.gserviceaccount.com',
      'uploadServiceAccount':
          'upload@customer-media-123.iam.gserviceaccount.com',
      'workloadIdentityProvider':
          'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
      'authProjectId': 'example-platform',
      'webOrigin': 'https://ii-os.example.com',
      'githubAppId': '123456',
      'githubAppSecret':
          'projects/customer-media-123/secrets/github-app-private-key',
    });

    expect(connection.projectId, 'customer-media-123');
    expect(connection.workspaceId, '123e4567-e89b-42d3-a456-426614174000');
    expect(connection.webOrigin, 'https://ii-os.example.com');
    expect(connection.toJson(), isNot(contains('privateKey')));
  });

  test('an organization connection serves every workspace inside it', () {
    final session = SessionModel.fromJson({
      'user': {
        'uid': 'owner-1',
        'email': 'owner@example.com',
        'displayName': 'Owner',
        'isOwner': false,
      },
      'organizations': [
        {
          'organization': {
            'id': '123e4567-e89b-42d3-a456-426614174000',
            'name': 'Acme',
            'connection': {
              'schemaVersion': 3,
              'organizationId': '123e4567-e89b-42d3-a456-426614174000',
              'projectId': 'customer-media-123',
              'projectNumber': '123456789012',
              'databaseId': 'ii-os-data',
              'region': 'us-central1',
              'bucket': 'customer-media-assets',
              'dataServiceAccount':
                  'broker@example-platform.iam.gserviceaccount.com',
              'uploadServiceAccount':
                  'upload@customer-media-123.iam.gserviceaccount.com',
              'workloadIdentityProvider':
                  'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
              'authProjectId': 'example-platform',
              'webOrigin': 'https://ii-os.example.com',
              'githubAppId': '123456',
              'githubAppSecret':
                  'projects/customer-media-123/secrets/github-app-private-key',
            },
          },
          'membership': {
            'role': 'owner',
            'roleLabel': 'Owner',
            'effectiveCapabilities': ['org.workspaces.create'],
          },
        },
      ],
      'workspaces': [
        {
          'workspace': {
            'id': 'workspace-friends',
            'name': 'Friends',
            'organizationId': '123e4567-e89b-42d3-a456-426614174000',
            'environment': 'dev',
            'repositories': <Object?>[],
            'projects': <Object?>[],
            'workflows': <Object?>[],
            'connection': null,
          },
          'membership': {
            'workspaceId': 'workspace-friends',
            'uid': 'owner-1',
            'email': 'owner@example.com',
            'role': 'owner',
            'roleLabel': 'Owner',
            'featureClaims': <Object?>[],
            'effectiveCapabilities': ['workspace.read'],
          },
        },
      ],
    });

    final connection = session.connectionForWorkspace('workspace-friends');

    expect(connection?.organizationId, '123e4567-e89b-42d3-a456-426614174000');
    expect(connection?.workspaceId, isEmpty);
    expect(connection?.bucket, 'customer-media-assets');
    expect(session.organizations.single.can('org.workspaces.create'), isTrue);
  });

  test('a workspace resolves only its selected organization GCP resource', () {
    final session = SessionModel.fromJson(
      _resourceSession(
        gcpGrants: [
          {
            'resourceId': 'gcp_media',
            'permissions': ['assets.read'],
            'primary': true,
          },
        ],
      ),
    );

    final organization = session.organizations.single;
    final workspace = session.workspaces.single.workspace;
    expect(organization.resources.gcp, hasLength(2));
    expect(workspace.resourceGrants.gcp.single.resourceId, 'gcp_media');
    expect(
      session.connectionForWorkspace('workspace-friends')?.projectId,
      'media-project',
    );
  });

  test(
    'an explicit empty workspace grant never inherits all GCP resources',
    () {
      final session = SessionModel.fromJson(
        _resourceSession(gcpGrants: const []),
      );

      expect(session.connectionForWorkspace('workspace-friends'), isNull);
    },
  );

  test('a child workspace resolves a promoted legacy GCP resource', () {
    final json = _resourceSession(
      gcpGrants: [
        {
          'resourceId': 'gcp_legacy_primary',
          'permissions': ['assets.read'],
          'primary': true,
        },
      ],
    );
    final organization =
        ((json['organizations']! as List<Object?>).single
                as Map<String, Object?>)['organization']!
            as Map<String, Object?>;
    organization['gcpResources'] = [_legacyGcpResource()];

    final session = SessionModel.fromJson(json);

    expect(
      session.connectionForWorkspace('workspace-friends')?.projectId,
      'legacy-project',
    );
    expect(
      session.organizations.single.resources.gcp.single.legacySourceWorkspaceId,
      'workspace-existing',
    );
  });

  test(
    'a workspace uses the server-resolved connection without the organization directory',
    () {
      final json = _resourceSession(
        gcpGrants: [
          {
            'resourceId': 'gcp_legacy_primary',
            'permissions': ['assets.read'],
            'primary': true,
          },
        ],
      );
      final organizations = json['organizations']! as List<Object?>;
      final organizationAccess = organizations.single! as Map<String, Object?>;
      final organization =
          organizationAccess['organization']! as Map<String, Object?>;
      final legacy = _legacyGcpResource();
      organization['gcpResources'] = [legacy];
      final workspaces = json['workspaces']! as List<Object?>;
      final workspaceAccess = workspaces.single! as Map<String, Object?>;
      final workspace = workspaceAccess['workspace']! as Map<String, Object?>;
      workspace['resolvedConnection'] = legacy['connection'];
      organizations.clear();

      final session = SessionModel.fromJson(json);

      expect(
        session.connectionForWorkspace('workspace-friends')?.projectId,
        'legacy-project',
      );
    },
  );

  test('reads a persisted organization connection', () {
    final connection = DataPlaneConnectionModel.fromJson({
      'schemaVersion': 3,
      'organizationId': '123e4567-e89b-42d3-a456-426614174000',
      'projectId': 'customer-media-123',
      'projectNumber': '123456789012',
      'databaseId': 'ii-os-data',
      'region': 'us-central1',
      'bucket': 'customer-media-assets',
      'dataServiceAccount': 'broker@example-platform.iam.gserviceaccount.com',
      'uploadServiceAccount':
          'upload@customer-media-123.iam.gserviceaccount.com',
      'workloadIdentityProvider':
          'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
      'authProjectId': 'example-platform',
      'webOrigin': 'https://ii-os.example.com',
      'githubAppId': '123456',
      'githubAppSecret':
          'projects/customer-media-123/secrets/github-app-private-key',
    });

    expect(connection.isOrganizationBound, isTrue);
    expect(connection.bindingId, '123e4567-e89b-42d3-a456-426614174000');
    expect(connection.toJson()['schemaVersion'], 3);
  });

  test('parses workflow model names and supports older template responses', () {
    final explicit = WorkflowTemplateModel.fromJson({
      'id': 'acme/media#image-edit',
      'workflowId': 'image-edit',
      'version': '1',
      'displayName': 'Acme Edit Workflow',
      'model': 'Acme Edit v2',
      'repository': 'acme/media',
      'enabled': true,
      'inputs': {
        'duration_seconds': {
          'type': 'number',
          'required': true,
          'minimum': 2,
          'maximum': 20,
          'default': 15,
        },
        'aspect_ratio': {
          'type': 'string',
          'required': true,
          'allowedValues': ['1:1', '3:2', '2:3'],
        },
      },
      'runtimeEstimates': [
        {
          'selector': {'performance_mode': 'turbo'},
          'durationInput': 'duration_seconds',
          'baselineOutputSeconds': 15,
          'baselineRuntimeSeconds': 900,
          'hardware': '24 GB GPU',
          'measuredAt': '2026-08-14',
        },
      ],
    });
    final legacy = WorkflowTemplateModel.fromJson({
      'id': 'acme/legacy#image-edit',
      'workflowId': 'image-edit',
      'version': '1',
      'displayName': 'Legacy Image Edit',
      'repository': 'acme/legacy',
      'enabled': true,
    });

    expect(explicit.model, 'Acme Edit v2');
    expect(explicit.inputs['duration_seconds']!.minimum, 2);
    expect(explicit.inputs['duration_seconds']!.maximum, 20);
    expect(explicit.inputs['duration_seconds']!.defaultNumber, 15);
    expect(explicit.inputs['aspect_ratio']!.allowedValues, [
      '1:1',
      '3:2',
      '2:3',
    ]);
    final estimate = explicit.estimateRuntime(const {
      'performance_mode': 'turbo',
      'duration_seconds': 5,
    });
    expect(estimate?.estimatedSeconds, 300);
    expect(estimate?.durationLabel, '5 minutes');
    expect(estimate?.hardware, '24 GB GPU');
    expect(legacy.model, 'Legacy Image Edit');
    expect(legacy.runtimeEstimates, isEmpty);
  });
}

Map<String, Object?> _resourceSession({
  required List<Map<String, Object?>> gcpGrants,
}) => {
  'user': {
    'uid': 'owner-1',
    'email': 'owner@example.com',
    'displayName': 'Owner',
    'isOwner': false,
  },
  'organizations': [
    {
      'organization': {
        'id': '123e4567-e89b-42d3-a456-426614174000',
        'name': 'Acme',
        'resourceCatalogVersion': 1,
        'gcpResources': [
          _gcpResource('gcp_media', 'media-project'),
          _gcpResource('gcp_data', 'data-project'),
        ],
        'githubResources': <Object?>[],
        'runnerPools': <Object?>[],
      },
      'membership': {
        'role': 'admin',
        'roleLabel': 'Organization Admin',
        'effectiveCapabilities': ['org.integrations.manage'],
      },
    },
  ],
  'workspaces': [
    {
      'workspace': {
        'id': 'workspace-friends',
        'name': 'Friends',
        'organizationId': '123e4567-e89b-42d3-a456-426614174000',
        'environment': 'dev',
        'repositories': <Object?>[],
        'projects': <Object?>[],
        'workflows': <Object?>[],
        'resourceGrantVersion': 1,
        'resourceGrants': {
          'gcp': gcpGrants,
          'github': <Object?>[],
          'runners': <Object?>[],
        },
      },
      'membership': {
        'workspaceId': 'workspace-friends',
        'uid': 'owner-1',
        'email': 'owner@example.com',
        'role': 'admin',
        'roleLabel': 'Workspace Admin',
        'effectiveCapabilities': ['workspace.read', 'workspace.manage'],
      },
    },
  ],
};

Map<String, Object?> _gcpResource(String id, String projectId) => {
  'id': id,
  'name': projectId,
  'connection': {
    'schemaVersion': 4,
    'organizationId': '123e4567-e89b-42d3-a456-426614174000',
    'projectId': projectId,
    'projectNumber': '123456789012',
    'databaseId': 'ii-os-data',
    'region': 'us-central1',
    'bucket': '$projectId-assets',
    'dataServiceAccount': 'broker@example-platform.iam.gserviceaccount.com',
    'uploadServiceAccount': 'upload@$projectId.iam.gserviceaccount.com',
    'workloadIdentityProvider':
        'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
    'authProjectId': 'example-platform',
    'webOrigin': 'https://ii-os.example.com',
  },
  'permissionEnvelope': ['assets.read', 'assets.write', 'workflows.upload'],
  'active': true,
};

Map<String, Object?> _legacyGcpResource() => {
  'id': 'gcp_legacy_primary',
  'name': 'Existing GCP project',
  'legacySourceWorkspaceId': 'workspace-existing',
  'connection': {
    'schemaVersion': 2,
    'workspaceId': 'workspace-existing',
    'projectId': 'legacy-project',
    'projectNumber': '123456789012',
    'databaseId': 'ii-os-data',
    'region': 'us-central1',
    'bucket': 'legacy-project-assets',
    'dataServiceAccount': 'broker@example-platform.iam.gserviceaccount.com',
    'uploadServiceAccount': 'upload@legacy-project.iam.gserviceaccount.com',
    'workloadIdentityProvider':
        'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
    'authProjectId': 'example-platform',
    'webOrigin': 'https://ii-os.example.com',
    'githubAppId': '123456',
    'githubAppSecret': 'projects/legacy-project/secrets/github-app',
  },
  'permissionEnvelope': ['assets.read', 'assets.write', 'workflows.upload'],
  'active': true,
};

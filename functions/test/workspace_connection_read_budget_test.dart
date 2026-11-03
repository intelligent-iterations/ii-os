import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:ii_os_functions/src/workspace_store.dart';
import 'package:test/test.dart';

import 'support/credential_firestore_fake.dart';

void main() {
  test(
    'fresh legacy tenant snapshot keeps fallback decision with one read',
    () async {
      final firestore = CredentialFirestoreFake();
      firestore.documents['workspaces/11111111-1111-4111-8111-111111111111'] = {
        'organizationId': '22222222-2222-4222-8222-222222222222',
        'connection': _connection.toJson(),
      };
      firestore
              .documents['organizations/22222222-2222-4222-8222-222222222222'] =
          {};
      final store = WorkspaceStore(firestore, emulated: true);
      final current = await store.getWorkspace(
        '11111111-1111-4111-8111-111111111111',
      );
      expect(firestore.reads, 2);
      final start = firestore.reads;
      final reused = await store.resolveConnection(
        current,
        permission: 'workflows.upload',
      );
      expect(
        firestore.reads - start,
        1,
        reason: 'Only the existing organization connection fallback is read.',
      );
      final beforeWrapper = firestore.reads;
      final loaded = await store.requireConnection(
        '11111111-1111-4111-8111-111111111111',
        permission: 'workflows.upload',
      );
      expect(firestore.reads - beforeWrapper, 3);
      expect(reused.toJson(), loaded.toJson());
      expect(reused.workspaceId, '11111111-1111-4111-8111-111111111111');
    },
  );

  test(
    'fresh snapshot and loading wrapper reject the same missing explicit grant',
    () async {
      final firestore = CredentialFirestoreFake();
      firestore.documents['workspaces/11111111-1111-4111-8111-111111111111'] = {
        'organizationId': '22222222-2222-4222-8222-222222222222',
        'connection': _connection.toJson(),
        'resourceGrantVersion': 1,
        'resourceGrants': {
          'gcp': <Object?>[],
          'github': <Object?>[],
          'runners': <Object?>[],
        },
      };
      firestore
              .documents['organizations/22222222-2222-4222-8222-222222222222'] =
          {};
      final store = WorkspaceStore(firestore, emulated: true);
      final current = await store.getWorkspace(
        '11111111-1111-4111-8111-111111111111',
      );
      final before = firestore.reads;
      final denied = isA<ApiError>().having(
        (error) => error.code,
        'code',
        'workspace_gcp_resource_required',
      );
      await expectLater(
        store.resolveConnection(current, permission: 'workflows.upload'),
        throwsA(denied),
      );
      expect(
        firestore.reads,
        before,
        reason: 'An explicit missing grant cannot reach a fallback.',
      );
      await expectLater(
        store.requireConnection(
          '11111111-1111-4111-8111-111111111111',
          permission: 'workflows.upload',
        ),
        throwsA(denied),
      );
      expect(firestore.reads - before, 2);
    },
  );
}

const _connection = DataPlaneConnection(
  workspaceId: '11111111-1111-4111-8111-111111111111',
  projectId: 'example-project',
  projectNumber: '123456789012',
  databaseId: '(default)',
  region: 'us-central1',
  bucket: 'example-private-assets',
  dataServiceAccount: 'broker@example-project.iam.gserviceaccount.com',
  uploadServiceAccount: 'upload@example-project.iam.gserviceaccount.com',
  workloadIdentityProvider:
      'projects/123456789012/locations/global/workloadIdentityPools/example/providers/example',
  authProjectId: 'example-control',
  webOrigin: 'https://example.test',
  githubAppId: '123',
  githubAppSecret: 'projects/example-project/secrets/example-app',
  emulated: true,
);

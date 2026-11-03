import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';

import '../../data_plane_connection.dart';
import '../../provider_contracts/artifact_storage_gateway.dart';
import '../../workspace_store.dart';

final class GcsArtifactStorageGatewayResolver
    implements ArtifactStorageGatewayResolver {
  const GcsArtifactStorageGatewayResolver(this.store);

  final WorkspaceStore store;

  @override
  Future<ArtifactStorageGateway> resolve(
    String workspaceId, {
    required String permission,
  }) async => GcsArtifactStorageGateway(
    await store.requireConnection(workspaceId, permission: permission),
  );
}

final class GcsArtifactStorageGateway implements ArtifactStorageGateway {
  const GcsArtifactStorageGateway(this.connection);

  final DataPlaneConnection connection;

  @override
  bool get verifiesRemoteObjects => !connection.emulated;

  @override
  Future<ArtifactUploadContract> createUploadContract() async =>
      ArtifactUploadContract(
        provider: 'gcp_wif',
        fields: {
          'bucket': connection.bucket,
          'workloadIdentityProvider': connection.workloadIdentityProvider,
          'serviceAccount': connection.uploadServiceAccount,
        },
      );

  @override
  Future<List<ArtifactObjectMetadata>> readMetadata(
    List<ArtifactObjectLocator> objects,
  ) async {
    if (!verifiesRemoteObjects) return const [];
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final api = storage.StorageApi(client);
      final metadata = <ArtifactObjectMetadata>[];
      for (final object in objects) {
        final remote = await api.objects.get(
          connection.bucket,
          object.path,
          generation: object.version,
        );
        if (remote is! storage.Object) {
          throw StateError('GCS returned an invalid object response.');
        }
        metadata.add(
          ArtifactObjectMetadata(
            version: remote.generation ?? '',
            sizeBytes: int.tryParse(remote.size ?? '') ?? -1,
            contentType: remote.contentType ?? '',
            sha256: remote.metadata?['ii-os-sha256'] ?? '',
            crc32c: remote.crc32c,
          ),
        );
      }
      return metadata;
    } finally {
      client.close();
    }
  }
}

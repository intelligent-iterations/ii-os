final class ArtifactUploadContract {
  const ArtifactUploadContract({required this.provider, required this.fields});

  final String provider;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {...fields, 'provider': provider};
}

final class ArtifactObjectLocator {
  const ArtifactObjectLocator({required this.path, required this.version});

  final String path;
  final String version;
}

final class ArtifactObjectMetadata {
  const ArtifactObjectMetadata({
    required this.version,
    required this.sizeBytes,
    required this.contentType,
    required this.sha256,
    this.crc32c,
  });

  final String version;
  final int sizeBytes;
  final String contentType;
  final String sha256;
  final String? crc32c;
}

/// A workspace-bound artifact data plane. Implementations own provider SDK
/// calls and translate their metadata into the common ii-os contract.
abstract interface class ArtifactStorageGateway {
  bool get verifiesRemoteObjects;

  Future<ArtifactUploadContract> createUploadContract();

  Future<List<ArtifactObjectMetadata>> readMetadata(
    List<ArtifactObjectLocator> objects,
  );
}

abstract interface class ArtifactStorageGatewayResolver {
  Future<ArtifactStorageGateway> resolve(
    String workspaceId, {
    required String permission,
  });
}

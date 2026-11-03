import 'dart:typed_data';

import '../services/api_client.dart';
import '../services/source_asset_uploader.dart';

/// Network boundary for source assets used by generation workflows.
abstract interface class SourceAssetRepository {
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  });
}

final class SourceAssetApiRepository implements SourceAssetRepository {
  const SourceAssetApiRepository(this.api);

  final ApiClient api;

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) => SourceAssetUploader(api).upload(
    workspaceId: workspaceId,
    filename: filename,
    bytes: bytes,
    contentType: contentType,
    expectedBucket: expectedBucket,
    ghostMode: ghostMode,
  );
}

part of 'workflow_api.dart';

extension WorkflowSourceAssetRead on WorkflowApi {
  /// Authorizes reading one stored source asset, so an attached reference can
  /// be previewed after its bytes have left the browser.
  ///
  /// Returns null when the request is not a source-asset read, letting the
  /// caller fall through to the upload routes.
  Future<Response?> _sourceAssetReadUrl(
    Request request,
    String requestId,
    String workspaceId,
    List<String> path,
  ) async {
    if (request.method != 'GET' || path.length != 6 || path[5] != 'read-url') {
      return null;
    }
    final grant = await sourceAssets.readGrant(
      workspaceId: workspaceId,
      assetId: path[4],
    );
    if (grant.identity.sha256 == null) {
      // Without a digest the client cannot prove the bytes it downloads match
      // the record, so refuse rather than hand out an unverifiable grant.
      throw const ApiError(
        409,
        'asset_metadata_invalid',
        'The asset metadata is unavailable.',
      );
    }
    return jsonResponse(200, {'data': grant.toJson()}, requestId: requestId);
  }
}

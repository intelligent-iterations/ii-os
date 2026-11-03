import '../models/models.dart';
import '../models/production_line.dart';
import '../services/api_client.dart';

/// The single owner of `v1/workspaces/{id}/production-lines`.
///
/// The list route returns only the lines the caller may see. Visibility is
/// resolved on the server against line membership, never filtered here -- a
/// client-side filter is a display choice, not an access boundary.
abstract interface class ProductionLineRepository {
  Future<List<ProductionLineModel>> list(String workspaceId);

  Future<ProductionLineModel> create(String workspaceId, JsonMap body);

  Future<ProductionLineModel> update(
    String workspaceId,
    String lineId,
    JsonMap body,
  );

  Future<void> delete(String workspaceId, String lineId);
}

final class ProductionLineApiRepository implements ProductionLineRepository {
  const ProductionLineApiRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ProductionLineModel>> list(String workspaceId) async {
    final response = await _api.get(_path(workspaceId));
    final lines = response['productionLines'];
    if (lines is! List<Object?>) return const [];
    return lines
        .whereType<JsonMap>()
        .map(ProductionLineModel.fromJson)
        .toList();
  }

  @override
  Future<ProductionLineModel> create(String workspaceId, JsonMap body) async {
    final response = await _api.post(_path(workspaceId), body: body);
    return ProductionLineModel.fromJson(_line(response));
  }

  @override
  Future<ProductionLineModel> update(
    String workspaceId,
    String lineId,
    JsonMap body,
  ) async {
    final response = await _api.patch(
      '${_path(workspaceId)}/$lineId',
      body: body,
    );
    return ProductionLineModel.fromJson(_line(response));
  }

  @override
  Future<void> delete(String workspaceId, String lineId) =>
      _api.delete('${_path(workspaceId)}/$lineId');

  String _path(String workspaceId) =>
      'v1/workspaces/$workspaceId/production-lines';

  /// Mutating routes are audited, so they answer under `data`; the read route
  /// answers with the record directly.
  JsonMap _line(JsonMap response) {
    final data = response['data'];
    if (data is JsonMap) return data;
    final line = response['productionLine'];
    return line is JsonMap ? line : response;
  }
}

import 'dart:convert';

import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'api_error.dart';
import 'auth_service.dart';

final class AuditSink {
  AuditSink({
    required this.projectId,
    required this.datasetId,
    required this.tableId,
  });

  final String projectId;
  final String datasetId;
  final String tableId;
  BigqueryApi? _api;

  bool get isConfigured =>
      projectId.isNotEmpty && datasetId.isNotEmpty && tableId.isNotEmpty;

  Future<void> record({
    required String requestId,
    required AuthenticatedUser actor,
    required String action,
    required String phase,
    String? workspaceId,
    String? targetType,
    String? targetId,
    Map<String, Object?> metadata = const {},
  }) async {
    final row = <String, Object?>{
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'request_id': requestId,
      'actor_uid': actor.uid,
      'actor_email': actor.email,
      'workspace_id': workspaceId,
      'action': action,
      'phase': phase,
      'target_type': targetType,
      'target_id': targetId,
      'metadata_json': jsonEncode(metadata),
    };
    // Structured stdout remains useful if BigQuery is temporarily unavailable.
    print(jsonEncode({'kind': 'ii_os.audit', ...row}));
    if (!isConfigured) return;

    try {
      final api = await _bigQuery();
      final response = await api.tabledata.insertAll(
        TableDataInsertAllRequest(
          traceId: requestId.length <= 36
              ? requestId
              : requestId.substring(0, 36),
          rows: [
            TableDataInsertAllRequestRows(
              insertId: '$requestId:$phase',
              json: row,
            ),
          ],
        ),
        projectId,
        datasetId,
        tableId,
      );
      if (response.insertErrors?.isNotEmpty ?? false) {
        throw StateError('BigQuery rejected the audit row');
      }
    } catch (_) {
      throw const ApiError(
        503,
        'audit_unavailable',
        'The action was blocked because its audit record could not be stored.',
      );
    }
  }

  Future<BigqueryApi> _bigQuery() async {
    final existing = _api;
    if (existing != null) return existing;
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [BigqueryApi.bigqueryInsertdataScope],
    );
    return _api = BigqueryApi(client);
  }
}

import 'dart:convert';

import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../../error_reporter.dart';

typedef BigQueryErrorInsert =
    Future<void> Function({
      required Map<String, Object?> row,
      required String rowId,
    });

final class BigQueryErrorSink implements ErrorEventSink {
  BigQueryErrorSink({
    required this.projectId,
    required this.datasetId,
    required this.tableId,
    this.insert,
  });

  final String projectId;
  final String datasetId;
  final String tableId;
  final BigQueryErrorInsert? insert;
  BigqueryApi? _api;

  bool get isConfigured =>
      projectId.isNotEmpty && datasetId.isNotEmpty && tableId.isNotEmpty;

  @override
  Future<void> write(ErrorRecord record) async {
    if (!isConfigured) {
      throw StateError('BigQuery error storage is not configured');
    }
    final row = <String, Object?>{
      'occurred_at': record.occurredAt.toUtc().toIso8601String(),
      'received_at': record.receivedAt.toUtc().toIso8601String(),
      'schema_version': record.schemaVersion,
      'environment': record.environment,
      'source': record.source,
      'error_type': record.errorType,
      'error_message': record.errorMessage,
      'stack_trace': record.stackTrace.isEmpty ? null : record.stackTrace,
      'request_id': record.requestId,
      'related_request_id': record.relatedRequestId,
      'route': record.route,
      'workspace_id': record.workspaceId,
      'actor_key': record.actorKey,
      'breadcrumbs_json': jsonEncode([
        for (final breadcrumb in record.breadcrumbs) breadcrumb.toJson(),
      ]),
    };
    await (insert ?? _insert)(row: row, rowId: record.requestId);
  }

  Future<void> _insert({
    required Map<String, Object?> row,
    required String rowId,
  }) async {
    final response = await (await _bigQuery()).tabledata.insertAll(
      TableDataInsertAllRequest(
        traceId: rowId.length <= 36 ? rowId : rowId.substring(0, 36),
        rows: [TableDataInsertAllRequestRows(insertId: rowId, json: row)],
      ),
      projectId,
      datasetId,
      tableId,
    );
    if (response.insertErrors?.isNotEmpty ?? false) {
      throw StateError('BigQuery rejected the error row');
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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'agent_usage_event.dart';
import 'agent_usage_query.dart';
import 'agent_usage_report.dart';
import 'api_error.dart';

const Set<int> agentUsageWindows = {7, 30, 90};
const Set<String> agentUsageOrigins = {'all', 'local', 'cloud', 'unknown'};

/// Ceiling on bytes a single report query may bill.
///
/// The query aggregates in BigQuery and prunes to the requested partitions, so
/// a realistic workspace stays under the 10 MiB minimum bill. This exists so a
/// pathological table cannot turn one dashboard load into a large bill: the
/// query fails closed rather than scanning without limit.
const int agentUsageMaximumBytesBilled = 256 * 1024 * 1024;

final class AgentUsageQueryResult {
  const AgentUsageQueryResult({
    required this.rows,
    this.bytesProcessed,
    this.cacheHit,
  });

  final List<Map<String, Object?>> rows;
  final int? bytesProcessed;
  final bool? cacheHit;
}

typedef AgentUsageQuery =
    Future<AgentUsageQueryResult> Function({
      required String workspaceId,
      required int days,
      required String origin,
    });

typedef AgentUsageInsert =
    Future<void> Function(List<Map<String, Object?>> rows);

final class AgentUsageStore {
  AgentUsageStore({
    required this.projectId,
    required this.datasetId,
    required this.tableId,
    this.query,
    this.insert,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  final String projectId;
  final String datasetId;
  final String tableId;
  final AgentUsageQuery? query;
  final AgentUsageInsert? insert;
  final DateTime Function() _clock;
  BigqueryApi? _api;

  bool get isConfigured =>
      projectId.isNotEmpty && datasetId.isNotEmpty && tableId.isNotEmpty;

  Future<Map<String, Object?>> ingest({
    required String workspaceId,
    required String reporterId,
    required List<Map<String, Object?>> events,
  }) async {
    if (!isConfigured) {
      throw const ApiError(
        503,
        'agent_usage_not_configured',
        'Agent usage storage is not configured for this environment.',
      );
    }
    if (events.isEmpty || events.length > 100) {
      throw const ApiError(
        400,
        'invalid_agent_usage_event_batch',
        'Send between 1 and 100 agent usage events per request.',
      );
    }
    final receivedAt = _clock().toUtc();
    final parsed = [
      for (final event in events) AgentUsageEvent.parse(event, now: receivedAt),
    ];
    final rows = [
      for (final event in parsed)
        ...event.bigQueryRows(
          workspaceId: workspaceId,
          reporterId: reporterId,
          receivedAt: receivedAt,
        ),
    ];
    try {
      await (insert ?? _insertBigQuery)(rows);
    } on ApiError {
      rethrow;
    } on Object {
      throw const ApiError(
        503,
        'agent_usage_ingest_unavailable',
        'Agent usage could not be stored in BigQuery.',
      );
    }
    return <String, Object?>{
      'accepted': parsed.length,
      'rows': rows.length,
      'receivedAt': receivedAt.toIso8601String(),
    };
  }

  Future<Map<String, Object?>> read({
    required String workspaceId,
    required int days,
    required String origin,
  }) async {
    if (!agentUsageWindows.contains(days)) {
      throw const ApiError(
        400,
        'invalid_agent_usage_window',
        'Choose a 7, 30, or 90 day usage window.',
      );
    }
    if (!agentUsageOrigins.contains(origin)) {
      throw const ApiError(
        400,
        'invalid_agent_usage_origin',
        'Choose all, local, cloud, or unknown agent usage.',
      );
    }
    if (!isConfigured) {
      return emptyAgentUsageReport(
        configured: false,
        days: days,
        origin: origin,
      );
    }
    try {
      final result = await (query ?? _queryBigQuery)(
        workspaceId: workspaceId,
        days: days,
        origin: origin,
      );
      return buildAgentUsageReport(result, days: days, origin: origin);
    } on ApiError {
      rethrow;
    } on Object {
      throw const ApiError(
        503,
        'agent_usage_unavailable',
        'Agent usage could not be loaded from BigQuery.',
      );
    }
  }

  Future<AgentUsageQueryResult> _queryBigQuery({
    required String workspaceId,
    required int days,
    required String origin,
  }) async {
    final today = _clock().toUtc();
    final sinceDate = today.subtract(Duration(days: days - 1));
    // The upper bound keeps partition pruning tight. Ingest accepts events up
    // to ten minutes ahead of now, so tomorrow is the furthest a row can land.
    final untilDate = today.add(const Duration(days: 1));
    final response = await (await _bigQuery()).jobs.query(
      QueryRequest(
        query: agentUsageReportSql(_qualifiedTable()),
        parameterMode: 'NAMED',
        queryParameters: [
          _parameter('scope_id', 'STRING', workspaceId),
          _parameter('since_date', 'DATE', _dateOnly(sinceDate)),
          _parameter('until_date', 'DATE', _dateOnly(untilDate)),
          _parameter('origin', 'STRING', origin),
        ],
        useLegacySql: false,
        useQueryCache: true,
        maximumBytesBilled: agentUsageMaximumBytesBilled.toString(),
        maxResults: agentUsageRowLimit,
        timeoutMs: 20000,
      ),
      projectId,
    );
    if (response.jobComplete != true || response.errors?.isNotEmpty == true) {
      throw StateError('BigQuery agent usage query did not complete');
    }
    final names = response.schema?.fields
        ?.map((field) => field.name ?? '')
        .toList();
    if (names == null || names.any((name) => name.isEmpty)) {
      throw StateError('BigQuery agent usage schema was missing');
    }
    return AgentUsageQueryResult(
      rows: (response.rows ?? const <TableRow>[]).map((row) {
        final cells = row.f ?? const <TableCell>[];
        return <String, Object?>{
          for (var index = 0; index < names.length; index++)
            names[index]: index < cells.length ? cells[index].v : null,
        };
      }).toList(),
      bytesProcessed: int.tryParse(response.totalBytesProcessed ?? ''),
      cacheHit: response.cacheHit,
    );
  }

  Future<void> _insertBigQuery(List<Map<String, Object?>> rows) async {
    final response = await (await _bigQuery()).tabledata.insertAll(
      TableDataInsertAllRequest(
        ignoreUnknownValues: false,
        skipInvalidRows: false,
        traceId: _traceId(rows),
        rows: [
          for (final row in rows)
            TableDataInsertAllRequestRows(insertId: _insertId(row), json: row),
        ],
      ),
      projectId,
      datasetId,
      tableId,
    );
    if (response.insertErrors?.isNotEmpty == true) {
      throw StateError('BigQuery rejected agent usage rows');
    }
  }

  String _qualifiedTable() {
    final identifier = RegExp(r'^[A-Za-z0-9_-]{1,1024}$');
    if (!identifier.hasMatch(projectId) ||
        !identifier.hasMatch(datasetId) ||
        !identifier.hasMatch(tableId)) {
      throw StateError('BigQuery agent usage identifiers are invalid');
    }
    return '$projectId.$datasetId.$tableId';
  }

  Future<BigqueryApi> _bigQuery() async {
    final existing = _api;
    if (existing != null) return existing;
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [BigqueryApi.bigqueryScope],
    );
    return _api = BigqueryApi(client);
  }
}

QueryParameter _parameter(String name, String type, String value) =>
    QueryParameter(
      name: name,
      parameterType: QueryParameterType(type: type),
      parameterValue: QueryParameterValue(value: value),
    );

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _traceId(List<Map<String, Object?>> rows) {
  final first = rows.isEmpty ? 'agent-usage' : '${rows.first['report_id']}';
  return sha256.convert(utf8.encode(first)).toString().substring(0, 36);
}

String _insertId(Map<String, Object?> row) => sha256
    .convert(
      utf8.encode(
        '${row['report_id']}\n${row['row_kind']}\n'
        '${row['agent_source'] ?? ''}\n${row['model'] ?? ''}',
      ),
    )
    .toString();

DateTime _utcNow() => DateTime.now().toUtc();

import 'package:ii_os_functions/src/error_reporter.dart';
import 'package:ii_os_functions/src/providers/gcp/bigquery_error_sink.dart';
import 'package:test/test.dart';

void main() {
  test(
    'maps a normalized error record to one idempotent BigQuery row',
    () async {
      Map<String, Object?>? inserted;
      String? insertId;
      final sink = BigQueryErrorSink(
        projectId: 'example-project',
        datasetId: 'ii_os',
        tableId: 'error_events',
        insert: ({required row, required rowId}) async {
          inserted = row;
          insertId = rowId;
        },
      );
      final record = ErrorRecord(
        schemaVersion: errorEventSchema,
        occurredAt: DateTime.utc(2026, 8, 25, 16, 20),
        receivedAt: DateTime.utc(2026, 8, 25, 16, 20, 1),
        environment: 'dev',
        source: 'api',
        errorType: 'github_graphql_failed',
        errorMessage: 'GitHub query failed.',
        stackTrace: 'frame 1',
        requestId: 'request-1',
        relatedRequestId: 'related-1',
        route: 'GET /v1/workspaces/workspace-1/projects',
        workspaceId: 'workspace-1',
        actorKey: 'actor-key',
        breadcrumbs: [
          ErrorBreadcrumb(
            occurredAt: DateTime.utc(2026, 8, 25, 16, 19, 59),
            category: 'api',
            name: 'request.failed',
            route: 'v1/workspaces/workspace-1/projects',
            requestId: 'related-1',
            statusCode: 502,
          ),
        ],
      );

      await sink.write(record);

      expect(insertId, 'request-1');
      expect(inserted?['schema_version'], errorEventSchema);
      expect(inserted?['occurred_at'], '2026-08-25T16:20:00.000Z');
      expect(inserted?['workspace_id'], 'workspace-1');
      expect(inserted?['actor_key'], 'actor-key');
      expect(inserted?['breadcrumbs_json'], contains('request.failed'));
      expect(inserted.toString(), isNot(contains('actor_uid')));
    },
  );

  test('fails closed when BigQuery identifiers are not configured', () async {
    final sink = BigQueryErrorSink(
      projectId: '',
      datasetId: '',
      tableId: 'error_events',
    );

    await expectLater(
      sink.write(
        ErrorRecord(
          schemaVersion: errorEventSchema,
          occurredAt: DateTime.utc(2026),
          receivedAt: DateTime.utc(2026),
          environment: 'dev',
          source: 'api',
          errorType: 'StateError',
          errorMessage: 'failed',
          stackTrace: '',
          requestId: 'request-1',
          breadcrumbs: const [],
        ),
      ),
      throwsStateError,
    );
  });
}

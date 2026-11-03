import 'dart:convert';

import 'package:ii_os_functions/src/api.dart';
import 'package:ii_os_functions/src/auth_service.dart';
import 'package:ii_os_functions/src/client_error_rate_limiter.dart';
import 'package:ii_os_functions/src/error_reporter.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'authenticated client envelope reaches the durable error sink',
    () async {
      final sink = _RecordingErrorSink();
      final now = DateTime.utc(2026, 8, 25, 16, 20);
      final request = Request(
        'POST',
        Uri.parse('https://ii-os.example/api?route=v1/client-errors'),
        body: jsonEncode({
          'schemaVersion': errorEventSchema,
          'occurredAt': now.toIso8601String(),
          'source': 'flutter.framework',
          'errorType': 'StateError',
          'message': 'Bearer secret-value failed',
          'stackTrace': 'frame 1',
          'route': '/workspaces/workspace-1/workshop?token=private',
          'workspaceId': 'workspace-1',
          'relatedRequestId': 'failed-request-1',
          'breadcrumbs': [
            {
              'occurredAt': now
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
              'category': 'api',
              'name': 'request.failed',
              'route': '/v1/workspaces/workspace-1/projects?token=private',
              'requestId': 'failed-request-1',
              'statusCode': 502,
            },
          ],
        }),
      );
      const actor = AuthenticatedUser(
        uid: 'user-1',
        email: 'person@example.com',
        emailVerified: true,
        displayName: 'person',
        isOwner: false,
      );

      final response = await handleClientErrorReport(
        request: request,
        requestId: 'ingest-request-1',
        actor: actor,
        rateLimiter: ClientErrorRateLimiter(clock: () => now),
        errors: ErrorReporter(
          environment: 'dev',
          sink: sink,
          clock: () => now,
          log: (_) {},
        ),
        clock: () => now,
      );

      expect(response.statusCode, 202);
      expect(response.headers['x-request-id'], 'ingest-request-1');
      expect(sink.records, hasLength(1));
      final record = sink.records.single;
      expect(record.requestId, 'ingest-request-1');
      expect(record.relatedRequestId, 'failed-request-1');
      expect(record.workspaceId, 'workspace-1');
      expect(record.actorKey, isNot('user-1'));
      expect(record.errorMessage, isNot(contains('secret-value')));
      expect(record.route, '/workspaces/workspace-1/workshop');
      expect(
        record.breadcrumbs.single.route,
        '/v1/workspaces/workspace-1/projects',
      );
    },
  );
}

final class _RecordingErrorSink implements ErrorEventSink {
  final List<ErrorRecord> records = [];

  @override
  Future<void> write(ErrorRecord record) async {
    records.add(record);
  }
}

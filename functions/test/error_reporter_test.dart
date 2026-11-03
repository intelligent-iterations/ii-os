import 'dart:async';
import 'dart:convert';

import 'package:ii_os_functions/src/error_reporter.dart';
import 'package:test/test.dart';

void main() {
  test(
    'writes redacted detail to the sink and only a summary to logs',
    () async {
      final logs = <String>[];
      final sink = _RecordingErrorSink();
      final reporter = ErrorReporter(
        environment: 'dev',
        log: logs.add,
        sink: sink,
        clock: () => DateTime.utc(2026, 8, 25, 16, 20),
      );

      await reporter.report(
        ErrorEvent(
          source: 'flutter.image',
          errorType: 'NetworkImageLoadException',
          message: 'Bearer abc.def token=super-secret failed',
          stackTrace:
              'https://hooks.slack.com/services/T000/B000/secret '
              'X-Goog-Signature=signed-secret at frame 1',
          requestId: 'request-123',
          route: '/history?token=do-not-log',
          workspaceId: 'workspace-1',
          actorUid: 'user-1',
          relatedRequestId: 'failed-request-1',
          breadcrumbs: [
            ErrorBreadcrumb(
              occurredAt: DateTime.utc(2026, 8, 25, 16, 19, 59),
              category: 'api',
              name: 'request.failed',
              route: '/v1/workspaces/workspace-1/projects?token=secret',
              requestId: 'failed-request-1',
              statusCode: 502,
            ),
          ],
        ),
      );

      final logged = (jsonDecode(logs.single) as Map).cast<String, Object?>();
      expect(logged['severity'], 'ERROR');
      expect(logged['serviceContext'], {'service': 'ii-os', 'version': 'dev'});
      final event = (logged['event'] as Map).cast<String, Object?>();
      expect(event['schemaVersion'], errorEventSchema);
      expect(event['source'], 'flutter.image');
      expect(event['requestId'], 'request-123');
      expect(event, isNot(contains('route')));
      expect(event, isNot(contains('workspaceId')));
      expect(event, isNot(contains('actorUid')));
      expect(event, isNot(contains('errorMessage')));
      expect(event, isNot(contains('stackTrace')));
      expect(logs.single, isNot(contains('super-secret')));
      expect(logs.single, isNot(contains('abc.def')));
      expect(logs.single, isNot(contains('/T000/B000/secret')));
      expect(logs.single, isNot(contains('signed-secret')));
      expect(logs.single, isNot(contains('do-not-log')));

      expect(sink.records, hasLength(1));
      final record = sink.records.single;
      expect(record.schemaVersion, errorEventSchema);
      expect(record.occurredAt, DateTime.utc(2026, 8, 25, 16, 20));
      expect(record.errorMessage, contains('token=[REDACTED]'));
      expect(record.route, '/history');
      expect(record.workspaceId, 'workspace-1');
      expect(record.actorKey, isNot('user-1'));
      expect(record.actorKey, hasLength(64));
      expect(record.relatedRequestId, 'failed-request-1');
      expect(
        record.breadcrumbs.single.route,
        '/v1/workspaces/workspace-1/projects',
      );
    },
  );

  test('bounds fields and omits absent optional context', () async {
    final logs = <String>[];
    final sink = _RecordingErrorSink();
    final reporter = ErrorReporter(
      environment: 'dev',
      log: logs.add,
      sink: sink,
    );

    await reporter.report(
      ErrorEvent(
        source: 'api',
        errorType: 'StateError',
        message: List.filled(1500, 'x').join(),
        stackTrace: 'frame 1',
        requestId: 'request-456',
        route: '/api',
      ),
    );

    final logged = (jsonDecode(logs.single) as Map).cast<String, Object?>();
    final event = (logged['event'] as Map).cast<String, Object?>();
    expect(event, isNot(contains('errorMessage')));
    expect(sink.records.single.errorMessage.length, 1200);
    expect(sink.records.single.workspaceId, isNull);
    expect(sink.records.single.actorKey, isNull);
  });

  test('a sink outage cannot replace the API error being reported', () async {
    final logs = <String>[];
    final reporter = ErrorReporter(
      environment: 'dev',
      log: logs.add,
      sink: _ThrowingErrorSink(),
    );

    await reporter.report(
      const ErrorEvent(
        source: 'api',
        errorType: 'StateError',
        message: 'request failed',
        stackTrace: 'frame 1',
        requestId: 'request-789',
        route: '/api',
      ),
    );

    expect(logs, hasLength(2));
    expect(logs.last, contains('error sink unavailable'));
    expect(logs.last, isNot(contains('request failed')));
  });

  test('a stalled sink cannot hold an API response indefinitely', () async {
    final logs = <String>[];
    final reporter = ErrorReporter(
      environment: 'dev',
      log: logs.add,
      sink: _StalledErrorSink(),
      sinkTimeout: const Duration(milliseconds: 5),
    );

    await reporter.report(
      const ErrorEvent(
        source: 'api',
        errorType: 'StateError',
        message: 'request failed',
        stackTrace: 'frame 1',
        requestId: 'request-timeout',
        route: '/api',
      ),
    );

    expect(logs, hasLength(2));
    expect(logs.last, contains('error sink unavailable'));
  });

  test('client breadcrumbs reject stale and unbounded input', () {
    final now = DateTime.utc(2026, 8, 25, 16, 20);
    final valid = ErrorBreadcrumb.parseList([
      {
        'occurredAt': now
            .subtract(const Duration(seconds: 2))
            .toIso8601String(),
        'category': 'api',
        'name': 'request.failed',
        'route': '/v1/workspaces/workspace-1/projects?token=secret',
        'requestId': 'request-1',
        'statusCode': 502,
      },
    ], now: now);

    expect(valid.single.route, '/v1/workspaces/workspace-1/projects');
    expect(valid.single.toJson().toString(), isNot(contains('secret')));
    expect(
      () => ErrorBreadcrumb.parseList(
        List<Object?>.filled(maximumErrorBreadcrumbs + 1, const {}),
        now: now,
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      () => parseClientErrorOccurredAt(
        now.subtract(const Duration(hours: 1)).toIso8601String(),
        now: now,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'caps durable error writes per instance while keeping summaries',
    () async {
      final logs = <String>[];
      final sink = _RecordingErrorSink();
      final reporter = ErrorReporter(
        environment: 'dev',
        log: logs.add,
        sink: sink,
        maximumSinkWritesPerMinute: 2,
        clock: () => DateTime.utc(2026, 8, 25, 16, 20),
      );

      for (var index = 0; index < 3; index++) {
        await reporter.report(
          ErrorEvent(
            source: 'api',
            errorType: 'StateError',
            message: 'failure $index',
            stackTrace: '',
            requestId: 'request-$index',
            route: '/api',
          ),
        );
      }

      expect(sink.records, hasLength(2));
      expect(logs, hasLength(4));
      expect(logs.last, contains('error sink rate limited'));
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

final class _ThrowingErrorSink implements ErrorEventSink {
  @override
  Future<void> write(ErrorRecord record) async {
    throw StateError('sink secret detail');
  }
}

final class _StalledErrorSink implements ErrorEventSink {
  @override
  Future<void> write(ErrorRecord record) => Completer<void>().future;
}

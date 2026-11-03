import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/services/client_breadcrumbs.dart';
import 'package:ii_os/services/client_error_reporter.dart';

void main() {
  test('redacts, bounds, and deduplicates client error reports', () async {
    final sent = <JsonMap>[];
    final now = DateTime.utc(2026, 8, 25, 16, 20);
    final breadcrumbs = ClientBreadcrumbs(clock: () => now)
      ..record(
        category: 'navigation',
        name: 'route',
        route: '/workspaces/workspace-1/tickets?prompt=private',
      )
      ..record(
        category: 'api',
        name: 'request.failed',
        route: 'v1/workspaces/workspace-1/projects?projectId=private',
        requestId: 'failed-request-1',
        statusCode: 502,
      );
    final reporter = ClientErrorReporter(
      breadcrumbs: breadcrumbs,
      clock: () => now,
      sender: (payload) async {
        sent.add(payload);
      },
    );
    addTearDown(reporter.close);
    const error = ApiFailure(
      'github_graphql_failed',
      'Bearer abc.def token=super-secret '
          'X-Goog-Signature=signed-secret failed',
      statusCode: 502,
      requestId: 'failed-request-1',
    );

    await reporter.report(
      error,
      StackTrace.fromString('frame 1'),
      source: 'history.thumbnail.image',
      route: '/signed/object?token=do-not-log',
      workspaceId: 'workspace-1',
    );
    await reporter.report(
      error,
      StackTrace.fromString('frame 1'),
      source: 'history.thumbnail.image',
      route: '/signed/object?token=do-not-log',
      workspaceId: 'workspace-1',
    );

    expect(sent, hasLength(1));
    expect(sent.single['message'], isNot(contains('abc.def')));
    expect(sent.single['message'], isNot(contains('super-secret')));
    expect(sent.single['message'], isNot(contains('signed-secret')));
    expect(sent.single['route'], '/signed/object');
    expect(sent.single['workspaceId'], 'workspace-1');
    expect(sent.single['schemaVersion'], 'ii-os.error.v2');
    expect(sent.single['errorType'], 'github_graphql_failed');
    expect(sent.single['occurredAt'], now.toIso8601String());
    expect(sent.single['relatedRequestId'], 'failed-request-1');
    final trail = (sent.single['breadcrumbs'] as List<Object?>).cast<JsonMap>();
    expect(trail, hasLength(2));
    expect(trail.last['statusCode'], 502);
    expect(trail.toString(), isNot(contains('private')));
  });

  test('does not report expected client validation failures', () async {
    final sent = <JsonMap>[];
    final reporter = ClientErrorReporter(
      sender: (payload) async {
        sent.add(payload);
      },
    );
    addTearDown(reporter.close);

    await reporter.report(
      const ApiFailure('invalid_input', 'Fix the input.', statusCode: 400),
      StackTrace.current,
      source: 'api.request',
    );

    expect(sent, isEmpty);
  });

  test('submits the safe envelope to the same-origin API route', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, Object?>? received;
    final handled = server.first.then((request) async {
      expect(request.uri.queryParameters['route'], 'v1/client-errors');
      received = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, Object?>();
      request.response
        ..statusCode = 202
        ..headers.contentType = ContentType.json
        ..write('{"accepted":true}');
      await request.response.close();
    });
    final api = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api',
      reportFailures: false,
      authTokenProvider: (_) async => 'test-token',
    );
    addTearDown(api.close);
    final reporter = ClientErrorReporter(
      api: api,
      clock: () => DateTime.utc(2026, 8, 25, 16, 20),
    );

    await reporter.report(
      StateError('token=private-value'),
      StackTrace.fromString('frame 1'),
      source: 'flutter.framework',
      route: '/workspaces/workspace-1/workshop?prompt=private',
    );
    await handled;

    expect(received?['schemaVersion'], 'ii-os.error.v2');
    expect(received?['route'], '/workspaces/workspace-1/workshop');
    expect(received?['workspaceId'], 'workspace-1');
    expect(received.toString(), isNot(contains('private-value')));
    expect(received.toString(), isNot(contains('prompt=private')));
  });
}

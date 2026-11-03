import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/services/client_breadcrumbs.dart';

void main() {
  test('API routing defaults to the deployment-owned same-origin endpoint', () {
    final client = ApiClient();
    addTearDown(client.close);

    expect(client.baseUrl, '/api');
  });

  test('public auth calls do not require or send a Firebase session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      expect(request.uri.queryParameters['route'], 'v1/auth/otp/start');
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('x-ii-os-read-policy'), 'explicit-v1');
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body, {'email': 'person@example.com'});
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"challengeId":"challenge-1"}');
      await request.response.close();
    });
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api',
      reportFailures: false,
    );
    addTearDown(client.close);

    final response = await client.postPublic(
      'v1/auth/otp/start',
      body: {'email': 'person@example.com'},
    );
    await handled;

    expect(response['challengeId'], 'challenge-1');
  });

  test('direct asset reads return bounded response bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      request.response
        ..contentLength = 4
        ..add([1, 2, 3, 4]);
      await request.response.close();
    });
    final client = ApiClient(baseUrl: '', reportFailures: false);
    addTearDown(client.close);

    final bytes = await client.getBytes(
      Uri.parse('http://127.0.0.1:${server.port}/asset'),
      maxBytes: 4,
    );
    await handled;

    expect(bytes, orderedEquals([1, 2, 3, 4]));
  });

  test(
    'direct asset reads reject an oversized response before buffering',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final handled = server.first.then((request) async {
        request.response
          ..contentLength = 4
          ..add([1, 2, 3, 4]);
        await request.response.close();
      });
      final client = ApiClient(baseUrl: '', reportFailures: false);
      addTearDown(client.close);

      await expectLater(
        client.getBytes(
          Uri.parse('http://127.0.0.1:${server.port}/asset'),
          maxBytes: 3,
        ),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.code,
            'code',
            'asset_download_too_large',
          ),
        ),
      );
      await handled;
    },
  );

  test('unexpected API failures notify the installed observer', () async {
    final failures = <Object>[];
    ApiClient.failureObserver = (error, stackTrace, route) async {
      failures.add(error);
      expect(route, 'v1/session');
    };
    addTearDown(() => ApiClient.failureObserver = null);
    final client = ApiClient(baseUrl: '');
    addTearDown(client.close);

    await expectLater(client.get('v1/session'), throwsA(isA<ApiFailure>()));
    await Future<void>.delayed(Duration.zero);

    expect(failures, hasLength(1));
  });

  test(
    'error-reporting API clients do not recursively notify observers',
    () async {
      var calls = 0;
      ApiClient.failureObserver = (error, stackTrace, route) async {
        calls += 1;
      };
      addTearDown(() => ApiClient.failureObserver = null);
      final client = ApiClient(baseUrl: '', reportFailures: false);
      addTearDown(client.close);

      await expectLater(
        client.get('v1/client-errors'),
        throwsA(isA<ApiFailure>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
    },
  );

  test('records API failure breadcrumbs with the server request id', () async {
    final breadcrumbs = ClientBreadcrumbs();
    ClientBreadcrumbs.install(breadcrumbs);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      request.response
        ..statusCode = 502
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'server-request-1')
        ..write(
          '{"error":{"code":"github_graphql_failed",'
          '"message":"The project could not be loaded."}}',
        );
      await request.response.close();
    });
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api',
      reportFailures: false,
    );
    addTearDown(client.close);

    await expectLater(
      client.postPublic('v1/workspaces/workspace-1/projects', body: const {}),
      throwsA(
        isA<ApiFailure>()
            .having((error) => error.statusCode, 'statusCode', 502)
            .having(
              (error) => error.requestId,
              'requestId',
              'server-request-1',
            ),
      ),
    );
    await handled;

    final trail = breadcrumbs.snapshot();
    expect(trail, hasLength(2));
    expect(trail.first['name'], 'request.started');
    expect(trail.last['name'], 'request.failed');
    expect(trail.last['requestId'], 'server-request-1');
    expect(trail.last['statusCode'], 502);
  });
}

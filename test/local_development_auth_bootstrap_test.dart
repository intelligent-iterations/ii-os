import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/providers/firebase/local_development_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled bootstrap performs no request or sign-in', () async {
    var requests = 0;
    var exchanges = 0;
    final bootstrap = LocalDevelopmentAuthBootstrap(
      enabled: false,
      baseUri: Uri.parse('http://127.0.0.1:5010/'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
      hasSession: () async => false,
      exchangeCustomToken: (_) async => exchanges++,
    );

    expect(await bootstrap.run(), isFalse);
    expect(requests, 0);
    expect(exchanges, 0);
  });

  test('an existing Firebase session skips the local token endpoint', () async {
    var requests = 0;
    final bootstrap = LocalDevelopmentAuthBootstrap(
      enabled: true,
      baseUri: Uri.parse('http://127.0.0.1:5010/'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
      hasSession: () async => true,
      exchangeCustomToken: (_) async {},
    );

    expect(await bootstrap.run(), isFalse);
    expect(requests, 0);
  });

  test(
    'takes one same-origin token and exchanges it without persistence',
    () async {
      const token = 'header.payload.signature';
      final requests = <http.Request>[];
      final exchanged = <String>[];
      final bootstrap = LocalDevelopmentAuthBootstrap(
        enabled: true,
        baseUri: Uri.parse('http://127.0.0.1:5010/workspaces/example'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'customToken': token}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        hasSession: () async => false,
        exchangeCustomToken: (value) async => exchanged.add(value),
      );

      expect(await bootstrap.run(), isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(
        requests.single.url,
        Uri.parse('http://127.0.0.1:5010/_ii/local-auth'),
      );
      expect(exchanged, [token]);
    },
  );

  test('rejects a missing or oversized token without echoing it', () async {
    for (final body in <String>[
      '{}',
      jsonEncode({'customToken': 'x' * 16 * 1024}),
    ]) {
      final bootstrap = LocalDevelopmentAuthBootstrap(
        enabled: true,
        baseUri: Uri.parse('http://127.0.0.1:5010/'),
        client: MockClient((_) async => http.Response(body, 200)),
        hasSession: () async => false,
        exchangeCustomToken: (_) async => fail('must not exchange'),
      );

      await expectLater(
        bootstrap.run(),
        throwsA(
          isA<LocalDevelopmentAuthException>().having(
            (error) => error.toString(),
            'sanitized message',
            isNot(contains('xxxx')),
          ),
        ),
      );
    }
  });

  test('emulator bootstrap creates its synthetic local account once', () async {
    final creates = <String>[];
    final signsIn = <String>[];
    final bootstrap = LocalEmulatorAuthBootstrap(
      enabled: true,
      email: 'owner@example.com',
      hasSession: () async => false,
      createAccount: (email) async => creates.add(email),
      signIn: (email) async => signsIn.add(email),
    );

    expect(await bootstrap.run(), isTrue);
    expect(creates, ['owner@example.com']);
    expect(signsIn, isEmpty);
  });

  test('emulator bootstrap signs in when its account already exists', () async {
    final signsIn = <String>[];
    final bootstrap = LocalEmulatorAuthBootstrap(
      enabled: true,
      email: 'owner@example.com',
      hasSession: () async => false,
      createAccount: (_) async =>
          throw const LocalEmulatorAccountExistsException(),
      signIn: (email) async => signsIn.add(email),
    );

    expect(await bootstrap.run(), isTrue);
    expect(signsIn, ['owner@example.com']);
  });
}

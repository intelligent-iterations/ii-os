import 'dart:convert';
import 'dart:io';

import 'package:ii_os_functions/src/otp_email_sender.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sends the ZeptoMail API contract without placing secrets in URLs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final handled = server.first.then((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1.1/email');
        expect(request.uri.query, isEmpty);
        expect(
          request.headers.value('authorization'),
          'Zoho-enczapikey test-mail-api-key',
        );
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['from'], {
          'address': 'noreply@example.com',
          'name': 'ii-os',
        });
        expect((body['to'] as List).single, {
          'email_address': {'address': 'person@example.com'},
        });
        expect(body['textbody'], contains('123456'));
        request.response.statusCode = 201;
        await request.response.close();
      });
      final sender = ZeptoMailOtpSender(
        apiKey: 'test-mail-api-key',
        fromAddress: 'noreply@example.com',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1.1/email'),
      );

      await sender.send(email: 'person@example.com', code: '123456');
      await handled;
    },
  );

  test('does not expose an API key in configuration errors', () {
    const secret = 'highly-sensitive-mail-key';

    expect(
      () => ZeptoMailOtpSender(apiKey: secret, fromAddress: 'not-an-email'),
      throwsA(predicate<Object>((error) => !error.toString().contains(secret))),
    );
  });
}

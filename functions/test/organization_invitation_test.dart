import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/transactional_mail.dart';
import 'package:test/test.dart';

void main() {
  group('workspace access suspension', () {
    Membership membership({bool suspended = false}) => Membership.fromData({
      'workspaceId': 'workspace-1',
      'uid': 'user-1',
      'email': 'user@example.com',
      'role': 'editor',
      'featureClaims': ['workspace.read', 'jobs.trigger'],
      if (suspended) 'status': 'suspended',
    });

    test('a membership written before suspension existed is active', () {
      expect(membership().suspended, isFalse);
      expect(membership().allows(Capability.jobsTrigger), isTrue);
    });

    test('suspending withdraws every capability at once', () {
      final off = membership(suspended: true);

      // Enforced on the membership rather than at each route, so a caller that
      // forgets to ask cannot honour switched-off access.
      expect(off.effectiveCapabilities, isEmpty);
      expect(off.allows(Capability.workspaceRead), isFalse);
      expect(off.allows(Capability.jobsTrigger), isFalse);
    });

    test('the role and claims survive so restoring is not re-granting', () {
      final off = membership(suspended: true);

      expect(off.role, WorkspaceRole.editor);
      expect(off.featureClaims, contains('jobs.trigger'));
      expect(off.toJson()['suspended'], isTrue);
    });
  });

  group('invitation email', () {
    const message = OrganizationInviteEmail(
      organizationName: 'Intelligent Iterations',
      inviterEmail: 'admin@example.com',
      acceptUrl: 'https://ii-os.example.com/invitations/abc',
      expiresInDays: 7,
    );

    test('renders a branded invitation with a useful text fallback', () {
      expect(
        message.subject,
        'You\u2019re invited to Intelligent Iterations on ii-os',
      );
      expect(message.textBody, contains('admin@example.com'));
      expect(message.textBody, contains('7 days'));
      expect(message.textBody, contains('Open your invitation'));
      expect(message.htmlBody, contains('Creative operations, in motion.'));
      expect(message.htmlBody, contains('Your place in'));
      expect(message.htmlBody, contains('Accept invitation'));
      expect(message.htmlBody, contains('role="presentation"'));
      expect(message.htmlBody, contains('background-color:#171B1F'));
      expect(message.htmlBody, contains('color:#5ED6B2'));
      expect(
        message.htmlBody,
        contains('https://ii-os.example.com/invitations/abc'),
      );
    });

    test('does not depend on remote images or tracking pixels', () {
      expect(message.htmlBody, isNot(contains('<img')));
      expect(message.htmlBody, isNot(contains('url(')));
      expect(message.htmlBody, isNot(contains('tracking')));
    });

    test('says plainly that the link is not a credential', () {
      // Collapsed because the copy is wrapped for readability in the source;
      // asserting on the wrapped form would break on a reflow rather than on a
      // meaning change.
      String flat(String value) => value.replaceAll(RegExp(r'\s+'), ' ');

      // Forwarding the mail hands the recipient nothing, so the copy should
      // not tell people to guard it as though it did.
      expect(flat(message.textBody), contains('only works for the address'));
      expect(flat(message.htmlBody), contains('only works for the address'));
      expect(flat(message.textBody), isNot(contains('do not share')));
    });

    test('escapes tenant-owned names in the HTML message', () {
      const untrusted = OrganizationInviteEmail(
        organizationName: '<script>organization</script>',
        inviterEmail: 'admin@example.com<script>',
        acceptUrl: 'https://ii-os.example/invitations/a?x=1&y=2',
        expiresInDays: 7,
      );

      expect(untrusted.htmlBody, isNot(contains('<script>')));
      expect(untrusted.htmlBody, contains('&lt;script&gt;'));
      expect(untrusted.htmlBody, contains('x=1&amp;y=2'));
    });
  });

  group('workspace access email', () {
    const message = WorkspaceAccessEmail(
      workspaceName: 'Campaign production',
      organizationName: 'Intelligent Iterations',
      workspaceUrl:
          'https://ii-os.example.com/workspaces/campaign-production/home',
    );

    test('is a notification with a direct workspace link', () {
      expect(message.subject, 'You now have access to Campaign production');
      expect(message.textBody, contains('Intelligent Iterations'));
      expect(message.htmlBody, contains('/campaign-production/home'));
    });
  });

  test(
    'Zepto transport sends the invitation to the requested recipient',
    () async {
      late http.Request captured;
      final mailer = ZeptoMailer(
        apiKey: 'test-api-key',
        fromAddress: 'noreply@example.com',
        endpoint: Uri.parse('https://mail.example/send'),
        client: MockClient((request) async {
          captured = request;
          return http.Response('{}', 201);
        }),
      );

      await mailer.send(
        to: 'invitee@example.com',
        message: const OrganizationInviteEmail(
          organizationName: 'Acme',
          inviterEmail: 'owner@example.com',
          acceptUrl: 'https://ii-os.example/invitations/one',
          expiresInDays: 7,
        ),
      );

      final body = jsonDecode(captured.body) as Map<String, Object?>;
      final recipients = body['to'] as List<Object?>;
      final recipient = recipients.single as Map<String, Object?>;
      final address = recipient['email_address'] as Map<String, Object?>;
      expect(address['address'], 'invitee@example.com');
      expect(captured.headers['authorization'], 'Zoho-enczapikey test-api-key');
      expect(body['subject'], 'You\u2019re invited to Acme on ii-os');
      expect(body['textbody'], contains('Open your invitation'));
      expect(body['htmlbody'], contains('Accept invitation'));
    },
  );

  test('Zepto rejection retains only safe provider diagnostics', () async {
    final mailer = ZeptoMailer(
      apiKey: 'test-api-key',
      fromAddress: 'noreply@example.com',
      endpoint: Uri.parse('https://mail.example/send'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'TM_4001',
              'details': [
                {
                  'code': 'SM_111',
                  'target': 'from',
                  'target_value': 'private-recipient@example.com',
                },
              ],
              'request_id': 'provider-request-1',
            },
          }),
          400,
        ),
      ),
    );

    Object? captured;
    try {
      await mailer.send(
        to: 'invitee@example.com',
        message: const OrganizationInviteEmail(
          organizationName: 'Acme',
          inviterEmail: 'owner@example.com',
          acceptUrl: 'https://ii-os.example/invitations/one',
          expiresInDays: 7,
        ),
      );
    } on Object catch (error) {
      captured = error;
    }

    expect(captured, isNotNull);
    expect('$captured', contains('HTTP 400'));
    expect('$captured', contains('TM_4001'));
    expect('$captured', contains('SM_111'));
    expect('$captured', contains('provider-request-1'));
    expect('$captured', isNot(contains('private-recipient@example.com')));
    expect('$captured', isNot(contains('invitee@example.com')));
  });

  group('sign-in email is unchanged', () {
    test('keeps the copy people already recognise', () {
      const message = SignInCodeEmail('123456');

      expect(message.subject, '123456 is your ii-os sign-in code');
      expect(message.textBody, contains('Your ii-os sign-in code is: 123456'));
      expect(message.textBody, contains('expires in 10 minutes'));
    });
  });
}

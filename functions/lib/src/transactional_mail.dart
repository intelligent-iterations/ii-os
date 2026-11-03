import 'dart:convert';

import 'package:http/http.dart' as http;

/// One message ii-os sends to a person.
///
/// Separated from the transport because the copy is the part that changes and
/// the transport is the part that must not. Adding a message should never mean
/// touching the code that authenticates to the mail provider.
abstract interface class TransactionalEmail {
  String get subject;
  String get textBody;
  String get htmlBody;
}

/// Sends a [TransactionalEmail] to one recipient.
abstract interface class TransactionalMailer {
  Future<void> send({required String to, required TransactionalEmail message});
}

/// A provider rejection with only bounded, non-content diagnostics retained.
///
/// ZeptoMail error bodies can echo field values, including recipient
/// addresses. Those values never leave the adapter; status, closed-form codes,
/// and the opaque provider request id are enough to diagnose the failure.
final class TransactionalMailRejected extends StateError {
  TransactionalMailRejected({
    required this.statusCode,
    this.providerCode,
    this.detailCodes = const [],
    this.requestId,
  }) : super('Transactional mail rejected');

  final int statusCode;
  final String? providerCode;
  final List<String> detailCodes;
  final String? requestId;

  @override
  String toString() => [
    'Transactional mail rejected: HTTP $statusCode',
    if (providerCode != null) 'provider code $providerCode',
    if (detailCodes.isNotEmpty) 'detail codes ${detailCodes.join(',')}',
    if (requestId != null) 'request $requestId',
  ].join('; ');
}

/// ZeptoMail transport.
///
/// The API key travels in a header and never in a URL, because a URL ends up
/// in logs, proxies, and error reports that a header does not.
final class ZeptoMailer implements TransactionalMailer {
  ZeptoMailer({
    required String apiKey,
    required this.fromAddress,
    http.Client? client,
    Uri? endpoint,
  }) : _apiKey = apiKey.trim(),
       _client = client ?? http.Client(),
       _endpoint =
           endpoint ?? Uri.parse('https://api.zeptomail.com/v1.1/email') {
    if (_apiKey.isEmpty) {
      throw ArgumentError('Mail API key is required.');
    }
    if (!emailPattern.hasMatch(fromAddress.trim())) {
      throw ArgumentError.value(
        fromAddress,
        'fromAddress',
        'A valid verified sender address is required.',
      );
    }
  }

  final String _apiKey;
  final String fromAddress;
  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<void> send({
    required String to,
    required TransactionalEmail message,
  }) async {
    final response = await _client
        .post(
          _endpoint,
          headers: {
            'accept': 'application/json',
            'authorization': 'Zoho-enczapikey $_apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'from': {'address': fromAddress.trim(), 'name': 'ii-os'},
            'to': [
              {
                'email_address': {'address': to},
              },
            ],
            'subject': message.subject,
            'textbody': message.textBody,
            'htmlbody': message.htmlBody,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mailRejection(response);
    }
  }
}

TransactionalMailRejected _mailRejection(http.Response response) {
  String? providerCode;
  String? requestId;
  final detailCodes = <String>[];
  try {
    final decoded = jsonDecode(response.body);
    final error = decoded is Map ? decoded['error'] : null;
    if (error is Map) {
      providerCode = _safeProviderIdentifier(error['code']);
      requestId = _safeProviderIdentifier(error['request_id'], maxLength: 120);
      final details = error['details'];
      if (details is List) {
        for (final detail in details.take(20)) {
          if (detail is! Map) continue;
          final code = _safeProviderIdentifier(detail['code']);
          if (code != null && !detailCodes.contains(code)) {
            detailCodes.add(code);
          }
        }
      }
    }
  } on FormatException {
    // The HTTP status remains useful when the provider returns a non-JSON
    // proxy or outage response. Never retain that untrusted response body.
  }
  return TransactionalMailRejected(
    statusCode: response.statusCode,
    providerCode: providerCode,
    detailCodes: detailCodes,
    requestId: requestId,
  );
}

String? _safeProviderIdentifier(Object? value, {int maxLength = 40}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
    return null;
  }
  return value;
}

/// The six-digit sign-in code.
///
/// Copy preserved exactly as it shipped: people recognise this message, and a
/// refactor of the transport is not a reason to reword it.
final class SignInCodeEmail implements TransactionalEmail {
  const SignInCodeEmail(this.code);

  final String code;

  @override
  String get subject => '$code is your ii-os sign-in code';

  @override
  String get textBody =>
      '''
Your ii-os sign-in code is: $code

It expires in 10 minutes and can be tried at most 3 times. If you did not
request this code, you can safely ignore this message.
''';

  @override
  String get htmlBody =>
      '''
<!doctype html>
<html><body style="font-family:Arial,sans-serif;color:#151515">
<p>Your ii-os sign-in code is:</p>
<p style="font-size:32px;font-weight:700;letter-spacing:8px">$code</p>
<p>It expires in 10 minutes and can be tried at most 3 times.</p>
<p>If you did not request this code, you can safely ignore this message.</p>
</body></html>
''';
}

/// An invitation to join an organization.
///
/// The link is a convenience, never a credential. Accepting still requires
/// signing in with the invited address and having verified it, so forwarding
/// this mail gives the recipient nothing -- which is why the body says so
/// rather than warning people to keep it secret.
final class OrganizationInviteEmail implements TransactionalEmail {
  const OrganizationInviteEmail({
    required this.organizationName,
    required this.inviterEmail,
    required this.acceptUrl,
    required this.expiresInDays,
  });

  final String organizationName;
  final String inviterEmail;
  final String acceptUrl;
  final int expiresInDays;

  @override
  String get subject => 'You\u2019re invited to $organizationName on ii-os';

  @override
  String get textBody =>
      '''
You\u2019re invited to $organizationName on ii-os.

$inviterEmail has made a place for you on their team.

Open your invitation:
$acceptUrl

Sign in with the email address that received this message. The invitation only
works for the address that received it, so the link itself is not a credential.

This invitation expires in $expiresInDays days. If you were not expecting it,
you can safely ignore this message.

ii-os \u2014 Creative operations, in motion.
''';

  @override
  String get htmlBody {
    final escapedOrganization = const HtmlEscape().convert(organizationName);
    final escapedInviter = const HtmlEscape().convert(inviterEmail);
    final escapedUrlAttribute = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(acceptUrl);
    final escapedUrlText = const HtmlEscape().convert(acceptUrl);
    return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>You\u2019re invited to $escapedOrganization</title>
</head>
<body style="margin:0;padding:0;background-color:#F2F5F4;color:#171B1F;
             font-family:Arial,Helvetica,sans-serif;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent">
  $escapedInviter invited you to join $escapedOrganization on ii-os.
</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0"
       border="0" style="width:100%;background-color:#F2F5F4">
  <tr>
    <td align="center" style="padding:32px 16px">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0"
             border="0" style="width:100%;max-width:640px;background-color:#FFFFFF;
             border:1px solid #DDE5E2;border-radius:20px;overflow:hidden">
        <tr>
          <td style="padding:24px 28px;background-color:#171B1F;
                     border-bottom:5px solid #5ED6B2">
            <table role="presentation" cellspacing="0" cellpadding="0" border="0">
              <tr>
                <td width="46" height="46" align="center" valign="middle"
                    style="width:46px;height:46px;background-color:#232A2D;
                           border:1px solid #3B4647;border-radius:12px;
                           color:#5ED6B2;font-size:22px;font-weight:800;
                           letter-spacing:-3px">ii&nbsp;</td>
                <td style="padding-left:14px">
                  <div style="color:#F4F6F5;font-size:20px;font-weight:700;
                              letter-spacing:-0.4px">ii-os</div>
                  <div style="padding-top:3px;color:#AAB5B3;font-size:12px;
                              letter-spacing:0.2px">Creative operations, in motion.</div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:42px 40px 18px">
            <div style="margin-bottom:18px;color:#0B7661;font-size:12px;
                        font-weight:800;letter-spacing:1.6px;text-transform:uppercase">
              Team invitation
            </div>
            <h1 style="margin:0;color:#171B1F;font-size:36px;line-height:1.15;
                       font-weight:750;letter-spacing:-1.2px">
              Your place in<br><span style="color:#0B7661">$escapedOrganization</span>
              is ready.
            </h1>
            <p style="margin:22px 0 0;color:#46524F;font-size:17px;line-height:1.65">
              <strong style="color:#171B1F">$escapedInviter</strong> invited you
              to collaborate with their team in ii-os.
            </p>
          </td>
        </tr>
        <tr>
          <td style="padding:12px 40px 28px">
            <table role="presentation" cellspacing="0" cellpadding="0" border="0">
              <tr>
                <td align="center" style="background-color:#0B7661;border-radius:10px">
                  <a href="$escapedUrlAttribute"
                     style="display:inline-block;padding:15px 24px;color:#FFFFFF;
                            font-size:16px;font-weight:700;text-decoration:none">
                    Accept invitation
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:0 40px 30px">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0"
                   border="0" style="width:100%;background-color:#EAF7F2;
                   border-radius:12px">
              <tr>
                <td style="padding:18px 20px;color:#38504A;font-size:14px;
                           line-height:1.55">
                  <strong style="display:block;margin-bottom:4px;color:#155E4D">
                    Made for the right inbox
                  </strong>
                  Sign in with the email address that received this message.
                  The invitation only works for the address that received it.
                  The link is a signpost, not a credential.
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:0 40px 40px;color:#6A7673;font-size:13px;line-height:1.6">
            <p style="margin:0 0 12px">
              This invitation expires in <strong>$expiresInDays days</strong>.
              If you were not expecting it, you can safely ignore this message.
            </p>
            <p style="margin:0 0 5px">Button not working? Open this address:</p>
            <p style="margin:0;word-break:break-all">
              <a href="$escapedUrlAttribute" style="color:#0B7661;text-decoration:underline">
                $escapedUrlText
              </a>
            </p>
          </td>
        </tr>
      </table>
      <p style="margin:18px 0 0;color:#83908D;font-size:12px;line-height:1.5">
        Sent by ii-os for $escapedOrganization
      </p>
    </td>
  </tr>
</table>
</body>
</html>
''';
  }
}

/// Notification that someone was given access to a project.
///
/// Not an invitation: the recipient is already in the tenant, so there is
/// nothing to accept and no link that grants anything.
final class WorkspaceAccessEmail implements TransactionalEmail {
  const WorkspaceAccessEmail({
    required this.workspaceName,
    required this.organizationName,
    required this.workspaceUrl,
  });

  final String workspaceName;
  final String organizationName;
  final String workspaceUrl;

  @override
  String get subject => 'You now have access to $workspaceName';

  @override
  String get textBody =>
      '''
You have been given access to $workspaceName in $organizationName on ii-os.

Open it:
$workspaceUrl
''';

  @override
  String get htmlBody {
    final escapedWorkspace = const HtmlEscape().convert(workspaceName);
    final escapedOrganization = const HtmlEscape().convert(organizationName);
    final escapedUrl = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(workspaceUrl);
    return '''
<!doctype html>
<html><body style="font-family:Arial,sans-serif;color:#151515;line-height:1.5">
<p>You have been given access to <strong>$escapedWorkspace</strong> in
$escapedOrganization on ii-os.</p>
<p><a href="$escapedUrl" style="color:#0B7661">Open $escapedWorkspace</a></p>
</body></html>
''';
  }
}

final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

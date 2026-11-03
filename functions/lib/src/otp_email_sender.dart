import 'package:http/http.dart' as http;

import 'transactional_mail.dart';

/// Sends the six-digit sign-in code.
///
/// Kept as its own interface so `PasswordlessAuthService` depends on the one
/// message it actually sends rather than on the whole mail surface. Sign-in is
/// the path that must never break for a reason belonging to some other feature.
abstract interface class OtpEmailSender {
  Future<void> send({required String email, required String code});
}

/// The sign-in code over ZeptoMail.
///
/// A thin adapter over [ZeptoMailer]: the transport, the API contract, and the
/// copy are all unchanged from when this class owned them directly.
final class ZeptoMailOtpSender implements OtpEmailSender {
  ZeptoMailOtpSender({
    required String apiKey,
    required String fromAddress,
    http.Client? client,
    Uri? endpoint,
  }) : _mailer = ZeptoMailer(
         apiKey: apiKey,
         fromAddress: fromAddress,
         client: client,
         endpoint: endpoint,
       );

  ZeptoMailOtpSender.using(this._mailer);

  final ZeptoMailer _mailer;

  String get fromAddress => _mailer.fromAddress;

  @override
  Future<void> send({required String email, required String code}) async {
    try {
      await _mailer.send(to: email, message: SignInCodeEmail(code));
    } on StateError {
      // The caller distinguishes delivery failure from every other error to
      // mark the challenge stale, and it matches on this message.
      throw StateError('Mail provider rejected the sign-in email.');
    }
  }
}

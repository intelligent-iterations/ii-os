import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'passwordless_auth_codec.dart';

/// Bounded send windows for the invitation endpoint.
///
/// The limiter is global across organizations. Otherwise an actor could create
/// or join several tenants and multiply the sending allowance for one address
/// or network source.
final class OrganizationInvitationRateLimiter {
  OrganizationInvitationRateLimiter({
    required this.firestore,
    required this.codec,
    this.maxEmailSendsPerWindow = 5,
    this.maxIpSendsPerWindow = 20,
    DateTime Function()? clock,
  }) : assert(maxEmailSendsPerWindow > 0),
       assert(maxIpSendsPerWindow > 0),
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const emailCollection = 'organizationInvitationEmailLimits';
  static const ipCollection = 'organizationInvitationIpLimits';
  static const resendCooldown = Duration(minutes: 1);
  static const rateWindow = Duration(hours: 1);
  static const retention = Duration(days: 1);

  final Firestore firestore;
  final PasswordlessAuthCodec codec;
  final int maxEmailSendsPerWindow;
  final int maxIpSendsPerWindow;
  final DateTime Function() _clock;

  Future<void> consume({
    required String email,
    required String clientIp,
    required String organizationId,
    required String actorUid,
  }) async {
    final emailRef = firestore
        .collection(emailCollection)
        .doc(codec.emailHash(email));
    final ipRef = firestore
        .collection(ipCollection)
        .doc(codec.ipHash(clientIp));
    final now = _clock();

    await firestore.runTransaction<void>((transaction) async {
      final emailSnapshot = await transaction.get(emailRef);
      final ipSnapshot = await transaction.get(ipRef);
      _enforceCooldown(emailSnapshot.data(), now);
      final emailWindow = _nextWindow(
        emailSnapshot.data(),
        now,
        maxEmailSendsPerWindow,
        code: 'too_many_invitation_emails',
        message:
            'Too many invitations were sent to this address. Try again later.',
      );
      final ipWindow = _nextWindow(
        ipSnapshot.data(),
        now,
        maxIpSendsPerWindow,
        code: 'too_many_invitation_requests',
        message: 'Too many invitations were requested. Try again later.',
      );
      final ownership = <String, Object?>{
        'lastOrganizationId': organizationId,
        'lastActorUid': actorUid,
        'deleteAt': Timestamp.fromDate(now.add(retention)),
      };
      transaction.set(emailRef, {
        ...emailWindow,
        ...ownership,
        'lastSentAt': Timestamp.fromDate(now),
      });
      transaction.set(ipRef, {...ipWindow, ...ownership});
    });
  }
}

void _enforceCooldown(Map<String, Object?>? state, DateTime now) {
  final lastSentAt = state?['lastSentAt'];
  if (lastSentAt is Timestamp &&
      now.difference(lastSentAt.toDate().toUtc()) <
          OrganizationInvitationRateLimiter.resendCooldown) {
    throw const ApiError(
      429,
      'invite_cooldown',
      'That address was invited moments ago. Try again shortly.',
    );
  }
}

Map<String, Object?> _nextWindow(
  Map<String, Object?>? state,
  DateTime now,
  int limit, {
  required String code,
  required String message,
}) {
  final startedAt = state?['windowStartedAt'];
  final active =
      startedAt is Timestamp &&
      now.difference(startedAt.toDate().toUtc()) <
          OrganizationInvitationRateLimiter.rateWindow;
  final count = active ? (state?['sendCount'] as int? ?? 0) : 0;
  if (count >= limit) throw ApiError(429, code, message);
  return {
    'windowStartedAt': active ? startedAt : Timestamp.fromDate(now),
    'sendCount': count + 1,
  };
}

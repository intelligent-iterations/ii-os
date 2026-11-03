import 'dart:convert';

import 'package:firebase_admin_sdk/auth.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'otp_email_sender.dart';
import 'passwordless_auth_codec.dart';

final class PasswordlessAuthService {
  PasswordlessAuthService({
    required FirebaseApp adminApp,
    required this.firestore,
    required this.codec,
    required this.sender,
    DateTime Function()? clock,
  }) : _auth = adminApp.auth(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const otpTtl = Duration(minutes: 10);
  static const magicTtl = Duration(minutes: 2);
  static const resendCooldown = Duration(minutes: 1);
  static const rateWindow = Duration(hours: 1);
  static const retention = Duration(days: 1);
  static const maxAttempts = 3;
  static const maxEmailSendsPerWindow = 5;
  static const maxIpSendsPerWindow = 20;

  final Auth _auth;
  final Firestore firestore;
  final PasswordlessAuthCodec codec;
  final OtpEmailSender sender;
  final DateTime Function() _clock;
  final Uuid _uuid = const Uuid();

  Future<Map<String, Object?>> start({
    required String email,
    required String clientNonce,
    required String clientIp,
  }) async {
    final normalizedEmail = _normalizedEmail(email);
    _validateNonce(clientNonce);
    final now = _clock();
    final challengeId = _uuid.v4();
    final otp = codec.newOtp();
    final challengeRef = firestore
        .collection('passwordlessAuthChallenges')
        .doc(challengeId);
    final emailRef = firestore
        .collection('passwordlessAuthEmailLimits')
        .doc(codec.emailHash(normalizedEmail));
    final ipRef = firestore
        .collection('passwordlessAuthIpLimits')
        .doc(codec.ipHash(clientIp));

    await firestore.runTransaction<void>((transaction) async {
      final emailSnapshot = await transaction.get(emailRef);
      final ipSnapshot = await transaction.get(ipRef);
      final emailState = emailSnapshot.data();
      final ipState = ipSnapshot.data();
      _enforceCooldown(emailState, now);
      final emailWindow = _nextWindow(emailState, now, maxEmailSendsPerWindow);
      final ipWindow = _nextWindow(ipState, now, maxIpSendsPerWindow);
      final activeId = emailState?['activeChallengeId'];
      DocumentReference<Map<String, Object?>>? activeRef;
      var activeExists = false;
      if (activeId is String && activeId.isNotEmpty) {
        activeRef = firestore
            .collection('passwordlessAuthChallenges')
            .doc(activeId);
        activeExists = (await transaction.get(activeRef)).exists;
      }
      if (activeRef != null && activeExists) {
        transaction.update(activeRef, {
          'status': 'stale',
          'staleReason': 'superseded',
          'updatedAt': Timestamp.fromDate(now),
        });
      }
      transaction.set(challengeRef, {
        'email': normalizedEmail,
        'emailHash': codec.emailHash(normalizedEmail),
        'otpHash': codec.otpHash(challengeId, otp),
        'bindingHash': codec.bindingHash(clientNonce),
        'status': 'pending_delivery',
        'attempts': 0,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(otpTtl)),
        'deleteAt': Timestamp.fromDate(now.add(retention)),
      });
      transaction.set(emailRef, {
        ...emailWindow,
        'activeChallengeId': challengeId,
        'lastSentAt': Timestamp.fromDate(now),
        'deleteAt': Timestamp.fromDate(now.add(retention)),
      });
      transaction.set(ipRef, {
        ...ipWindow,
        'deleteAt': Timestamp.fromDate(now.add(retention)),
      });
    });

    try {
      await sender.send(email: normalizedEmail, code: otp);
      await challengeRef.update({
        'status': 'pending',
        'deliveryAcceptedAt': Timestamp.fromDate(_clock()),
        'updatedAt': Timestamp.fromDate(_clock()),
      });
    } catch (_) {
      await challengeRef.update({
        'status': 'stale',
        'staleReason': 'delivery_failed',
        'updatedAt': Timestamp.fromDate(_clock()),
      });
      throw const ApiError(
        503,
        'email_delivery_unavailable',
        'The sign-in email could not be sent. Please try again shortly.',
      );
    }
    return {
      'challengeId': challengeId,
      'expiresInSeconds': otpTtl.inSeconds,
      'resendAfterSeconds': resendCooldown.inSeconds,
      'maxAttempts': maxAttempts,
    };
  }

  Future<Map<String, Object?>> verify({
    required String challengeId,
    required String code,
    required String clientNonce,
  }) async {
    _validateChallengeId(challengeId);
    _validateNonce(clientNonce);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const ApiError(400, 'invalid_code', 'Enter the 6-digit code.');
    }
    final ref = firestore
        .collection('passwordlessAuthChallenges')
        .doc(challengeId);
    final result = await firestore.runTransaction<Map<String, Object?>>((
      transaction,
    ) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      final now = _clock();
      _requireUsable(data, now, allowUnlocked: true);
      _requireBinding(data!, clientNonce);
      final expectedOtpHash = data['otpHash'];
      if (expectedOtpHash is! String ||
          !codec.matches(expectedOtpHash, codec.otpHash(challengeId, code))) {
        final attempts = (data['attempts'] as int? ?? 0) + 1;
        final remaining = maxAttempts - attempts;
        transaction.update(ref, {
          'attempts': attempts,
          'status': remaining == 0 ? 'stale' : data['status'],
          if (remaining == 0) 'staleReason': 'attempts_exhausted',
          'updatedAt': Timestamp.fromDate(now),
        });
        return {
          'errorCode': remaining == 0 ? 'challenge_stale' : 'incorrect_code',
          'remainingAttempts': remaining,
        };
      }
      final token = codec.newExchangeToken(challengeId, clientNonce);
      if (data['status'] != 'unlocked') {
        transaction.update(ref, {
          'status': 'unlocked',
          'exchangeHash': codec.exchangeHash(challengeId, token),
          'otpVerifiedAt': Timestamp.fromDate(now),
          'magicExpiresAt': Timestamp.fromDate(now.add(magicTtl)),
          'updatedAt': Timestamp.fromDate(now),
        });
      }
      return {'magicExchange': token, 'expiresInSeconds': magicTtl.inSeconds};
    });
    final errorCode = result['errorCode'];
    if (errorCode is String) {
      final remaining = result['remainingAttempts'] as int;
      throw ApiError(
        401,
        errorCode,
        remaining == 0
            ? 'This code is stale. Send a new code to continue.'
            : 'That code is incorrect.',
        details: {'remainingAttempts': remaining},
      );
    }
    return result;
  }

  Future<Map<String, Object?>> exchange({
    required String challengeId,
    required String magicExchange,
    required String clientNonce,
  }) async {
    _validateChallengeId(challengeId);
    _validateNonce(clientNonce);
    if (magicExchange.length < 40 || magicExchange.length > 100) {
      throw const ApiError(
        400,
        'invalid_exchange',
        'Sign-in proof is invalid.',
      );
    }
    final ref = firestore
        .collection('passwordlessAuthChallenges')
        .doc(challengeId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    final now = _clock();
    _requireUsable(data, now, allowUnlocked: true);
    _requireBinding(data!, clientNonce);
    if (data['status'] != 'unlocked' ||
        !_futureTimestamp(data['magicExpiresAt'], now) ||
        data['exchangeHash'] is! String ||
        !codec.matches(
          data['exchangeHash'] as String,
          codec.exchangeHash(challengeId, magicExchange),
        )) {
      throw const ApiError(
        410,
        'challenge_stale',
        'This sign-in proof is stale. Send a new code to continue.',
      );
    }
    final email = data['email'] as String;
    final user = await _verifiedUser(email);
    final customToken = await _auth.createCustomToken(
      user.uid,
      developerClaims: {'ii_os_auth_method': 'email_otp'},
    );
    await firestore.runTransaction<void>((transaction) async {
      final current = (await transaction.get(ref)).data();
      if (current?['status'] != 'unlocked' ||
          !_futureTimestamp(current?['magicExpiresAt'], _clock()) ||
          current?['exchangeHash'] is! String ||
          !codec.matches(
            current?['exchangeHash'] as String,
            codec.exchangeHash(challengeId, magicExchange),
          ) ||
          current?['bindingHash'] is! String ||
          !codec.matches(
            current?['bindingHash'] as String,
            codec.bindingHash(clientNonce),
          )) {
        throw const ApiError(
          410,
          'challenge_stale',
          'This sign-in proof has already been used.',
        );
      }
      transaction.update(ref, {
        'status': 'consumed',
        'consumedAt': Timestamp.fromDate(_clock()),
        'updatedAt': Timestamp.fromDate(_clock()),
      });
    });
    return {'customToken': customToken};
  }

  Future<UserRecord> _verifiedUser(String email) async {
    try {
      final user = await _auth.getUserByEmail(email);
      if (user.emailVerified) return user;
      return _auth.updateUser(user.uid, UpdateRequest(emailVerified: true));
    } on FirebaseAuthAdminException catch (error) {
      if (error.errorCode != AuthClientErrorCode.userNotFound) rethrow;
      try {
        return await _auth.createUser(
          CreateRequest(email: email, emailVerified: true),
        );
      } on FirebaseAuthAdminException catch (createError) {
        if (createError.errorCode != AuthClientErrorCode.emailAlreadyExists) {
          rethrow;
        }
        return _auth.getUserByEmail(email);
      }
    }
  }

  void _requireUsable(
    Map<String, Object?>? data,
    DateTime now, {
    required bool allowUnlocked,
  }) {
    final status = data?['status'];
    if (data == null ||
        (status != 'pending' && !(allowUnlocked && status == 'unlocked')) ||
        !_futureTimestamp(data['expiresAt'], now)) {
      throw const ApiError(
        410,
        'challenge_stale',
        'This code is stale. Send a new code to continue.',
      );
    }
  }

  void _requireBinding(Map<String, Object?> data, String nonce) {
    final expected = data['bindingHash'];
    if (expected is! String ||
        !codec.matches(expected, codec.bindingHash(nonce))) {
      throw const ApiError(
        410,
        'challenge_stale',
        'This code belongs to a different sign-in request.',
      );
    }
  }
}

Map<String, Object?> _nextWindow(
  Map<String, Object?>? state,
  DateTime now,
  int limit,
) {
  final startedAt = state?['windowStartedAt'];
  final active =
      startedAt is Timestamp &&
      now.difference(startedAt.toDate().toUtc()) <
          PasswordlessAuthService.rateWindow;
  final count = active ? (state?['sendCount'] as int? ?? 0) : 0;
  if (count >= limit) {
    throw const ApiError(
      429,
      'too_many_codes',
      'Too many codes were requested. Please try again later.',
    );
  }
  return {
    'windowStartedAt': active ? startedAt : Timestamp.fromDate(now),
    'sendCount': count + 1,
  };
}

void _enforceCooldown(Map<String, Object?>? state, DateTime now) {
  final lastSentAt = state?['lastSentAt'];
  if (lastSentAt is Timestamp &&
      now.difference(lastSentAt.toDate().toUtc()) <
          PasswordlessAuthService.resendCooldown) {
    throw const ApiError(
      429,
      'resend_too_soon',
      'Wait before sending another code.',
      details: {'retryAfterSeconds': 60},
    );
  }
}

bool _futureTimestamp(Object? value, DateTime now) =>
    value is Timestamp && value.toDate().toUtc().isAfter(now);

String _normalizedEmail(String email) {
  final value = email.trim().toLowerCase();
  if (value.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
    throw const ApiError(400, 'invalid_email', 'Enter a valid email address.');
  }
  return value;
}

void _validateNonce(String nonce) {
  try {
    final padded = nonce.padRight((nonce.length + 3) ~/ 4 * 4, '=');
    if (base64Url.decode(padded).length != 32) throw const FormatException();
  } on FormatException {
    throw const ApiError(
      400,
      'invalid_client_nonce',
      'The sign-in request is invalid.',
    );
  }
}

void _validateChallengeId(String challengeId) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(challengeId)) {
    throw const ApiError(
      400,
      'invalid_challenge',
      'Sign-in request is invalid.',
    );
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'retention.dart';

final class NotificationDevice {
  const NotificationDevice({required this.id, required this.token});

  final String id;
  final String token;
}

final class NotificationStore {
  const NotificationStore(this.firestore);

  final Firestore firestore;

  CollectionReference<Map<String, Object?>> get _notifications =>
      firestore.collection('notifications');

  CollectionReference<Map<String, Object?>> get _devices =>
      firestore.collection('notificationDevices');

  Future<List<Map<String, Object?>>> listForUser(String uid) async {
    final snapshot = await _notifications
        .where('uid', WhereFilter.equal, uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snapshot.docs
        .where((document) => !recordRetentionExpired(document.data()))
        .map((document) {
          final value = _jsonSafe(document.data());
          value['id'] = document.id;
          value.remove('uid');
          value.remove('deliveryAttempts');
          value.remove('deliveryStatus');
          value.remove('lastDeliveryError');
          return value;
        })
        .toList();
  }

  Future<void> markRead(String uid, String notificationId) async {
    final ref = _notifications.doc(_notificationId(notificationId));
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['uid'] != uid) {
      throw const ApiError(
        404,
        'notification_not_found',
        'Notification not found.',
      );
    }
    if (data['readAt'] == null) {
      await ref.update({'readAt': Timestamp.now()});
    }
  }

  Future<void> markAllRead(String uid) async {
    final snapshot = await _notifications
        .where('uid', WhereFilter.equal, uid)
        .where('readAt', WhereFilter.equal, null)
        .limit(100)
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = firestore.batch();
    for (final document in snapshot.docs) {
      batch.update(_notifications.doc(document.id), {
        FieldPath(const ['readAt']): Timestamp.now(),
      });
    }
    await batch.commit();
  }

  Future<void> registerDevice({
    required String uid,
    required String token,
    required String platform,
  }) async {
    final normalizedToken = _deviceToken(token);
    final now = Timestamp.now();
    await _devices.doc(notificationDeviceId(normalizedToken)).set({
      'uid': uid,
      'token': normalizedToken,
      'platform': _platform(platform),
      'updatedAt': now,
      'createdAt': now,
      'expiresAt': Timestamp.fromDate(
        now.toDate().toUtc().add(const Duration(days: 90)),
      ),
    });
  }

  Future<void> unregisterDevice({
    required String uid,
    required String token,
  }) async {
    final ref = _devices.doc(notificationDeviceId(_deviceToken(token)));
    final snapshot = await ref.get();
    if (snapshot.data()?['uid'] == uid) await ref.delete();
  }

  Future<List<NotificationDevice>> devicesForUser(String uid) async {
    final snapshot = await _devices
        .where('uid', WhereFilter.equal, uid)
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .get();
    return snapshot.docs
        .where((document) => !recordRetentionExpired(document.data()))
        .map(
          (document) => NotificationDevice(
            id: document.id,
            token: document.data()['token'] as String? ?? '',
          ),
        )
        .where((device) => device.token.isNotEmpty)
        .toList();
  }

  Future<Map<String, Object?>?> raw(String notificationId) async {
    final snapshot = await _notifications.doc(notificationId).get();
    return snapshot.data();
  }

  Future<void> recordDelivery(
    String notificationId, {
    required String status,
    String? error,
  }) async {
    final ref = _notifications.doc(notificationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return;
    await ref.update({
      'deliveryStatus': status,
      'deliveryAttempts':
          ((data['deliveryAttempts'] as num?)?.toInt() ?? 0) + 1,
      'lastDeliveryError': error,
      'lastDeliveryAt': Timestamp.now(),
      if (status == 'delivered') 'deliveredAt': Timestamp.now(),
    });
  }

  Future<void> removeDevice(String deviceId) => _devices.doc(deviceId).delete();
}

Map<String, Object?>? buildGenerationNotification({
  required Map<String, Object?> job,
  required List<Map<String, Object?>> artifacts,
  required Timestamp createdAt,
}) {
  final uid = job['createdBy'];
  final workspaceId = job['workspaceId'];
  final jobId = job['jobId'];
  if (uid is! String ||
      uid.isEmpty ||
      workspaceId is! String ||
      workspaceId.isEmpty ||
      jobId is! String ||
      jobId.isEmpty) {
    return null;
  }
  Map<String, Object?>? selected;
  var mediaKind = 'image';
  var selectedPriority = 0;
  for (final artifact in artifacts) {
    final contentType = artifact['content_type']?.toString() ?? '';
    final (candidateKind, priority) = switch (contentType) {
      _ when contentType.startsWith('video/') => ('video', 3),
      _ when contentType.startsWith('audio/') => ('audio', 2),
      _ when contentType.startsWith('image/') => ('image', 1),
      _ => ('', 0),
    };
    if (priority > selectedPriority) {
      selected = artifact;
      mediaKind = candidateKind;
      selectedPriority = priority;
    }
  }
  if (selected == null) return null;
  final requestedDeepLink = job['notificationDeepLink']?.toString().trim();
  final deepLink = requestedDeepLink == null || requestedDeepLink.isEmpty
      ? Uri(
          pathSegments: ['', 'workspaces', workspaceId, 'jobs', jobId],
        ).toString()
      : requestedDeepLink;
  final subject = _generationSubject(job);
  final title = subject == null
      ? switch (mediaKind) {
          'video' => 'Your video is ready',
          'audio' => _audioNotificationTitle(job),
          _ => 'Your image is ready',
        }
      : '$subject is ready';
  final prompt = _promptSnippet(job);
  return {
    'uid': uid,
    'workspaceId': workspaceId,
    'jobId': jobId,
    'type': 'generation.completed',
    'mediaKind': mediaKind,
    'artifactPath': selected['path'],
    'title': title,
    'body': prompt == null
        ? 'Your finished $mediaKind generation is ready to view.'
        : '\u201c$prompt\u201d',
    'deepLink': deepLink,
    'readAt': null,
    'createdAt': createdAt,
    'expiresAt': job['expiresAt'],
    'deliveryStatus': 'pending',
    'deliveryAttempts': 0,
  };
}

String _audioNotificationTitle(Map<String, Object?> job) {
  final workflowId = job['workflowId']?.toString().toLowerCase() ?? '';
  final workflowKey = job['workflowKey']?.toString().toLowerCase() ?? '';
  if (workflowId.startsWith('narration-create') ||
      workflowKey.startsWith('narration-create') ||
      workflowId.contains('narration') ||
      workflowKey.contains('narration')) {
    return 'Your narration is ready';
  }
  return 'Your song is ready';
}

String? _generationSubject(Map<String, Object?> job) {
  final inputs = job['inputs'];
  if (inputs is! Map) return null;
  for (final key in const [
    'characterName',
    'character_name',
    'storyboardName',
    'storyboard_name',
    'assetName',
    'name',
  ]) {
    final value = inputs[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value.length <= 80 ? value : '${value.substring(0, 77)}\u2026';
    }
  }
  return null;
}

String? _promptSnippet(Map<String, Object?> job) {
  final metadata = job['generationMetadata'];
  if (metadata is! Map) return null;
  final prompt = metadata['prompt']?.toString().trim();
  if (prompt == null || prompt.isEmpty) return null;
  final compact = prompt.replaceAll(RegExp(r'\s+'), ' ');
  return compact.length <= 120 ? compact : '${compact.substring(0, 117)}\u2026';
}

String notificationDeviceId(String token) =>
    sha256.convert(utf8.encode(token)).toString();

String _notificationId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 500 ||
      normalized.contains('/')) {
    throw const ApiError(
      400,
      'invalid_notification_id',
      'Notification ID is invalid.',
    );
  }
  return normalized;
}

String _deviceToken(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 4096) {
    throw const ApiError(
      400,
      'invalid_notification_token',
      'Notification token is invalid.',
    );
  }
  return normalized;
}

String _platform(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_-]{1,30}$').hasMatch(normalized)) {
    throw const ApiError(
      400,
      'invalid_notification_platform',
      'Notification platform is invalid.',
    );
  }
  return normalized;
}

Map<String, Object?> _jsonSafe(Map<String, Object?> data) {
  return data.map((key, value) => MapEntry(key, _jsonSafeValue(value)));
}

Object? _jsonSafeValue(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is List<Object?>) return value.map(_jsonSafeValue).toList();
  if (value is Map<String, Object?>) return _jsonSafe(value);
  return value;
}

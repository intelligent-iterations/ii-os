import 'package:firebase_admin_sdk/messaging.dart';

import 'notification_store.dart';

final class GenerationNotificationDispatcher {
  const GenerationNotificationDispatcher({
    required this.store,
    required this.messaging,
    required this.webOrigin,
  });

  final NotificationStore store;
  final Messaging messaging;
  final String webOrigin;

  Future<void> deliver(String notificationId) async {
    try {
      final notification = await store.raw(notificationId);
      if (notification == null ||
          notification['deliveryStatus'] == 'delivered') {
        return;
      }
      final uid = notification['uid'] as String? ?? '';
      final devices = await store.devicesForUser(uid);
      if (devices.isEmpty) {
        await _recordDelivery(notificationId, status: 'no_devices');
        return;
      }
      final deepLink = _absoluteDeepLink(
        notification['deepLink'] as String? ?? '/',
      );
      final response = await messaging.sendEachForMulticast(
        MulticastMessage(
          tokens: devices.map((device) => device.token).toList(),
          notification: Notification(
            title: notification['title'] as String?,
            body: notification['body'] as String?,
          ),
          data: {
            'type': notification['type']?.toString() ?? '',
            'notificationId': notificationId,
            'workspaceId': notification['workspaceId']?.toString() ?? '',
            'jobId': notification['jobId']?.toString() ?? '',
            'mediaKind': notification['mediaKind']?.toString() ?? '',
            'deepLink': deepLink,
          },
          webpush: WebpushConfig(
            headers: const {'TTL': '86400', 'Urgency': 'high'},
            fcmOptions: deepLink.startsWith('https://')
                ? WebpushFcmOptions(link: deepLink)
                : null,
          ),
        ),
      );
      for (var index = 0; index < response.responses.length; index += 1) {
        final result = response.responses[index];
        if (!result.success && _invalidToken(result.error?.code)) {
          await store.removeDevice(devices[index].id);
        }
      }
      await _recordDelivery(
        notificationId,
        status: response.successCount > 0 ? 'delivered' : 'failed',
        error: response.failureCount == 0
            ? null
            : '${response.failureCount} notification device(s) failed',
      );
    } on Object catch (error, stackTrace) {
      print(
        'ii-os generation notification delivery failed for '
        '$notificationId: $error\n$stackTrace',
      );
      await _recordDelivery(
        notificationId,
        status: 'failed',
        error: error.runtimeType.toString(),
      );
    }
  }

  Future<void> _recordDelivery(
    String notificationId, {
    required String status,
    String? error,
  }) async {
    try {
      await store.recordDelivery(notificationId, status: status, error: error);
    } on Object catch (recordError) {
      print(
        'ii-os generation notification status recording failed for '
        '$notificationId: $recordError',
      );
    }
  }

  String _absoluteDeepLink(String path) {
    final origin = Uri.tryParse(webOrigin.trim());
    if (origin == null || !origin.hasScheme || origin.host.isEmpty) return path;
    return origin.resolve(path).toString();
  }
}

bool _invalidToken(String? code) =>
    code == 'messaging/invalid-registration-token' ||
    code == 'messaging/registration-token-not-registered';

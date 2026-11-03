import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/generation_notification.dart';
import '../models/models.dart';
import 'api_client.dart';

enum PushAlertState {
  checking,
  available,
  enabled,
  blocked,
  unavailable,
  failed,
}

abstract interface class NotificationPushGateway {
  Stream<JsonMap> get foregroundMessages;

  Stream<JsonMap> get openedMessages;

  Stream<String> get tokenRefreshes;

  Future<bool> isSupported();

  Future<PushAlertState> permissionState();

  Future<PushAlertState> requestPermission();

  Future<String?> token();

  Future<void> deleteToken();

  Future<JsonMap?> initialMessage();
}

final class FirebaseNotificationPushGateway implements NotificationPushGateway {
  FirebaseNotificationPushGateway({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Stream<JsonMap> get foregroundMessages => FirebaseMessaging.onMessage.map(
    (message) => message.data.cast<String, Object?>(),
  );

  @override
  Stream<JsonMap> get openedMessages => FirebaseMessaging.onMessageOpenedApp
      .map((message) => message.data.cast<String, Object?>());

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Future<bool> isSupported() => FirebaseMessaging.instance.isSupported();

  @override
  Future<PushAlertState> permissionState() async {
    return _state(
      (await _messaging.getNotificationSettings()).authorizationStatus,
    );
  }

  @override
  Future<PushAlertState> requestPermission() async {
    final settings = await _messaging.requestPermission();
    if (!kIsWeb) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: true,
      );
    }
    return _state(settings.authorizationStatus);
  }

  @override
  Future<String?> token() => _messaging.getToken(
    vapidKey: AppConfig.firebaseWebVapidKey.trim().isEmpty
        ? null
        : AppConfig.firebaseWebVapidKey.trim(),
  );

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<JsonMap?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message?.data.cast<String, Object?>();
  }
}

final class GenerationNotificationService extends ChangeNotifier {
  GenerationNotificationService({
    required this.api,
    NotificationPushGateway? push,
  }) : push = push ?? FirebaseNotificationPushGateway();

  final ApiClient api;
  final NotificationPushGateway push;
  final StreamController<GenerationNotification> _arrivals =
      StreamController<GenerationNotification>.broadcast();
  final StreamController<String> _openedDeepLinks =
      StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Set<String> _knownIds = {};
  bool _started = false;
  bool _loading = false;
  bool _loadedOnce = false;
  List<GenerationNotification> _items = const [];
  PushAlertState _pushState = PushAlertState.checking;

  List<GenerationNotification> get items => _items;
  int get unreadCount => _items.where((item) => item.unread).length;
  PushAlertState get pushState => _pushState;
  Stream<GenerationNotification> get arrivals => _arrivals.stream;
  Stream<String> get openedDeepLinks => _openedDeepLinks.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscriptions
      ..add(push.foregroundMessages.listen(_receivePush))
      ..add(push.openedMessages.listen(_openPush))
      ..add(push.tokenRefreshes.listen(_registerToken))
      ..add(
        FirebaseAuth.instance.authStateChanges().listen((user) {
          if (user == null) unawaited(push.deleteToken());
        }),
      );
    await Future.wait([refresh(), _initializePush()]);
  }

  Future<PushAlertState> enablePush() async {
    try {
      _setPushState(await push.requestPermission());
      if (_pushState == PushAlertState.enabled) {
        await _registerCurrentToken();
      }
    } on Object {
      _setPushState(PushAlertState.failed);
    }
    return _pushState;
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final response = await api.get('v1/notifications');
      final next = (response['notifications'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .map(GenerationNotification.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();
      if (_loadedOnce) {
        for (final item in next.reversed) {
          if (!_knownIds.contains(item.id)) _arrivals.add(item);
        }
      }
      _knownIds
        ..clear()
        ..addAll(next.map((item) => item.id));
      _items = next;
      _loadedOnce = true;
      notifyListeners();
    } on Object {
      // Keep the last durable feed visible through transient API failures.
    } finally {
      _loading = false;
    }
  }

  Future<void> markRead(GenerationNotification notification) async {
    if (!notification.unread) return;
    final index = _items.indexWhere((item) => item.id == notification.id);
    if (index >= 0) {
      final next = [..._items];
      next[index] = next[index].markRead(DateTime.now());
      _items = next;
      notifyListeners();
    }
    try {
      await api.post(
        'v1/notifications/${Uri.encodeComponent(notification.id)}/read',
      );
    } on Object {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    final now = DateTime.now();
    _items = _items
        .map((item) => item.unread ? item.markRead(now) : item)
        .toList();
    notifyListeners();
    try {
      await api.post('v1/notifications/read-all');
    } on Object {
      await refresh();
    }
  }

  Future<void> markReadForJob(String jobId) async {
    final matches = _items.where((item) => item.jobId == jobId && item.unread);
    for (final notification in matches.toList()) {
      await markRead(notification);
    }
  }

  Future<void> _initializePush() async {
    try {
      if (!await push.isSupported()) {
        _setPushState(PushAlertState.unavailable);
        return;
      }
      _setPushState(await push.permissionState());
      if (_pushState == PushAlertState.available && !kIsWeb) {
        _setPushState(await push.requestPermission());
      }
      if (_pushState == PushAlertState.enabled) {
        await _registerCurrentToken();
      }
      final initial = await push.initialMessage();
      if (initial != null) _openPush(initial);
    } on Object {
      _setPushState(PushAlertState.failed);
    }
  }

  Future<void> _registerCurrentToken() async {
    final value = await push.token();
    if (value != null && value.isNotEmpty) await _registerToken(value);
  }

  Future<void> _registerToken(String token) async {
    try {
      await api.post(
        'v1/notification-devices',
        body: {'token': token, 'platform': _platformName()},
      );
      _setPushState(PushAlertState.enabled);
    } on Object {
      _setPushState(PushAlertState.failed);
    }
  }

  void _receivePush(JsonMap message) {
    unawaited(refresh());
  }

  void _openPush(JsonMap message) {
    final deepLink = notificationDeepLink(message['deepLink']?.toString());
    if (deepLink != '/') _openedDeepLinks.add(deepLink);
    unawaited(refresh());
  }

  void _setPushState(PushAlertState value) {
    if (_pushState == value) return;
    _pushState = value;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_arrivals.close());
    unawaited(_openedDeepLinks.close());
    super.dispose();
  }
}

PushAlertState _state(AuthorizationStatus value) => switch (value) {
  AuthorizationStatus.authorized ||
  AuthorizationStatus.provisional => PushAlertState.enabled,
  AuthorizationStatus.denied => PushAlertState.blocked,
  AuthorizationStatus.notDetermined => PushAlertState.available,
};

String _platformName() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform.name;
}

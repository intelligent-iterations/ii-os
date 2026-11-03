import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/generation_notification_service.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({
    required this.service,
    required this.onOpen,
    super.key,
  });

  final GenerationNotificationService service;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => PopupMenuButton<String>(
        tooltip: service.unreadCount == 0
            ? 'Notifications'
            : '${service.unreadCount} unread notifications',
        onOpened: () => unawaited(service.refresh()),
        onSelected: (value) => _select(context, value),
        itemBuilder: (context) => _items(),
        icon: _BellIcon(unreadCount: service.unreadCount),
      ),
    );
  }

  List<PopupMenuEntry<String>> _items() {
    final entries = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        enabled: false,
        child: Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ];
    if (kIsWeb && service.pushState != PushAlertState.enabled) {
      final canEnable =
          service.pushState == PushAlertState.available ||
          service.pushState == PushAlertState.failed;
      entries.add(
        PopupMenuItem<String>(
          value: canEnable ? _enablePush : null,
          enabled: canEnable,
          child: Row(
            children: [
              const Icon(LucideIcons.bellRing, size: 17),
              const SizedBox(width: 10),
              Expanded(child: Text(_pushLabel(service.pushState))),
            ],
          ),
        ),
      );
      entries.add(const PopupMenuDivider());
    }
    if (service.unreadCount > 0) {
      entries.add(
        const PopupMenuItem<String>(
          value: _markAllRead,
          child: Row(
            children: [
              Icon(LucideIcons.mailOpen, size: 17),
              SizedBox(width: 10),
              Text('Mark all as read'),
            ],
          ),
        ),
      );
      entries.add(const PopupMenuDivider());
    }
    if (service.items.isEmpty) {
      entries.add(
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('Generation updates will appear here.'),
        ),
      );
      return entries;
    }
    for (final notification in service.items.take(8)) {
      entries.add(
        PopupMenuItem<String>(
          value: 'notification:${notification.id}',
          child: SizedBox(
            width: 320,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(
                    notification.mediaKind == 'video'
                        ? LucideIcons.clapperboard
                        : LucideIcons.image,
                    size: 17,
                    color: notification.unread
                        ? IiOsColors.blue
                        : IiOsColors.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: IiOsColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return entries;
  }

  Future<void> _select(BuildContext context, String value) async {
    if (value == _enablePush) {
      final result = await service.enablePush();
      if (!context.mounted) return;
      final message = result == PushAlertState.enabled
          ? 'Browser alerts are enabled.'
          : 'Browser alerts could not be enabled.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (value == _markAllRead) {
      await service.markAllRead();
      return;
    }
    if (!value.startsWith('notification:')) return;
    final id = value.substring('notification:'.length);
    final notification = service.items
        .where((item) => item.id == id)
        .firstOrNull;
    if (notification == null) return;
    unawaited(service.markRead(notification));
    onOpen(notification.deepLink);
  }
}

const _markAllRead = 'mark-all-read';

class _BellIcon extends StatelessWidget {
  const _BellIcon({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(LucideIcons.bell, size: 19),
        if (unreadCount > 0)
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.xxs),
              decoration: BoxDecoration(
                color: IiOsColors.red,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: IiOsColors.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _pushLabel(PushAlertState state) => switch (state) {
  PushAlertState.available => 'Enable browser alerts',
  PushAlertState.blocked => 'Alerts blocked in browser settings',
  PushAlertState.unavailable => 'Alerts unavailable in this browser',
  PushAlertState.failed => 'Retry browser alerts',
  PushAlertState.checking => 'Checking browser alerts\u2026',
  PushAlertState.enabled => 'Browser alerts enabled',
};

const _enablePush = 'enable-push';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/generation_notification.dart';

void main() {
  test('parses durable unread generation notifications', () {
    final notification = GenerationNotification.fromJson(const {
      'id': 'job-1',
      'workspaceId': 'workspace-1',
      'jobId': 'job-1',
      'mediaKind': 'video',
      'title': 'Your video is ready',
      'body': 'Tap to view it.',
      'deepLink': '/workspaces/workspace-1/jobs/job-1',
      'createdAt': '2026-07-19T12:00:00.000Z',
      'readAt': null,
    });

    expect(notification.unread, isTrue);
    expect(notification.mediaKind, 'video');
    expect(notification.deepLink, '/workspaces/workspace-1/jobs/job-1');
    expect(notification.markRead(DateTime.utc(2026, 7, 19)).unread, isFalse);
  });

  test('keeps only same-app paths from absolute notification links', () {
    expect(
      notificationDeepLink(
        'https://ii-os.example.com/workspaces/w/jobs/j?source=push',
      ),
      '/workspaces/w/jobs/j?source=push',
    );
    expect(notificationDeepLink('javascript:alert(1)'), '/');
    expect(notificationDeepLink('relative/path'), '/');
  });
}

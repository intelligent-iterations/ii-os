import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/notification_store.dart';
import 'package:test/test.dart';

void main() {
  test('builds an exact image job deep link for its creator', () {
    final notification = buildGenerationNotification(
      job: {
        'createdBy': 'user-1',
        'workspaceId': 'workspace one',
        'jobId': 'job/image 7',
      },
      artifacts: [
        {
          'path': 'workspaces/workspace one/runs/job/image.png',
          'content_type': 'image/png',
        },
      ],
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 7, 19)),
    );

    expect(notification, isNotNull);
    expect(notification!['mediaKind'], 'image');
    expect(notification['title'], 'Your image is ready');
    expect(
      notification['deepLink'],
      '/workspaces/workspace%20one/jobs/job%2Fimage%207',
    );
  });

  test('prefers video when a completed job has mixed media artifacts', () {
    final notification = buildGenerationNotification(
      job: {
        'createdBy': 'user-1',
        'workspaceId': 'workspace-1',
        'jobId': 'job-1',
      },
      artifacts: [
        {'path': 'source.png', 'content_type': 'image/png'},
        {'path': 'result.mp4', 'content_type': 'video/mp4'},
      ],
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 7, 19)),
    );

    expect(notification!['mediaKind'], 'video');
    expect(notification['artifactPath'], 'result.mp4');
    expect(notification['title'], 'Your video is ready');
  });

  test('uses the generation subject and prompt in notification copy', () {
    final notification = buildGenerationNotification(
      job: {
        'createdBy': 'user-1',
        'workspaceId': 'workspace-1',
        'jobId': 'job-1',
        'inputs': {'characterName': 'Mira'},
        'generationMetadata': {'prompt': 'cinematic portrait at sunset'},
      },
      artifacts: [
        {'path': 'result.png', 'content_type': 'image/png'},
      ],
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 7, 19)),
    );

    expect(notification!['title'], 'Mira is ready');
    expect(notification['body'], '\u201ccinematic portrait at sunset\u201d');
  });

  test('builds a song notification for generated audio', () {
    final notification = buildGenerationNotification(
      job: {
        'createdBy': 'user-1',
        'workspaceId': 'workspace-1',
        'jobId': 'song-1',
      },
      artifacts: [
        {'path': 'song.mp3', 'content_type': 'audio/mpeg'},
      ],
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
    );

    expect(notification!['mediaKind'], 'audio');
    expect(notification['artifactPath'], 'song.mp3');
    expect(notification['title'], 'Your song is ready');
  });

  test('builds a narration notification for narration audio', () {
    final notification = buildGenerationNotification(
      job: {
        'createdBy': 'user-1',
        'workspaceId': 'workspace-1',
        'jobId': 'narration-1',
        'workflowId': 'narration-create-chatterbox-tts',
      },
      artifacts: [
        {'path': 'narration.mp3', 'content_type': 'audio/mpeg'},
      ],
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
    );

    expect(notification!['mediaKind'], 'audio');
    expect(notification['artifactPath'], 'narration.mp3');
    expect(notification['title'], 'Your narration is ready');
  });

  test('does not notify for a job without generated media', () {
    final notification = buildGenerationNotification(
      job: {
        'createdBy': 'user-1',
        'workspaceId': 'workspace-1',
        'jobId': 'job-1',
      },
      artifacts: [
        {'path': 'result.json', 'content_type': 'application/json'},
      ],
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 7, 19)),
    );

    expect(notification, isNull);
  });

  test('device IDs do not expose registration tokens', () {
    final id = notificationDeviceId('sensitive-fcm-registration-token');

    expect(id, hasLength(64));
    expect(id, isNot(contains('sensitive')));
    expect(id, notificationDeviceId('sensitive-fcm-registration-token'));
  });
}

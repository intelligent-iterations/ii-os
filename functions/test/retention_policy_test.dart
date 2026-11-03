import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/retention_policy.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 8, 23, 12);

void main() {
  group('window', () {
    test('an organization that set nothing keeps media for sixty days', () {
      expect(artifactRetentionDays(null), 60);
      expect(defaultArtifactRetentionDays, 60);
    });

    test('an organization keeps the window it configured', () {
      expect(artifactRetentionDays(14), 14);
    });

    test('a window longer than the ceiling is brought back to it', () {
      expect(artifactRetentionDays(365), 60);
    });

    test('a window of nothing still leaves a day', () {
      expect(artifactRetentionDays(0), 1);
      expect(artifactRetentionDays(-5), 1);
    });
  });

  group('expiry', () {
    test('counts from when the last thing let go', () {
      expect(
        artifactExpiry(retentionDays: 60, now: _now).toDate().toUtc(),
        _now.add(const Duration(days: 60)),
      );
    });
  });

  group('a play keeps media alive', () {
    test('pushes the window out again', () {
      final refreshed = refreshedArtifactExpiry(
        data: {
          'expiresAt': Timestamp.fromDate(_now.add(const Duration(days: 2))),
        },
        retentionDays: 60,
        now: _now,
      );

      expect(refreshed, isNotNull);
      expect(refreshed!.toDate().toUtc(), _now.add(const Duration(days: 60)));
    });

    test('leaves media that nothing is counting down alone', () {
      expect(
        refreshedArtifactExpiry(
          data: const {
            'assetAttachments': ['video-project/p/media/m'],
          },
          retentionDays: 60,
          now: _now,
        ),
        isNull,
      );
    });

    test('does not write again for a play moments after the last', () {
      expect(
        refreshedArtifactExpiry(
          data: {
            'expiresAt': Timestamp.fromDate(_now),
            'lastPlayedAt': Timestamp.fromDate(
              _now.subtract(const Duration(minutes: 5)),
            ),
          },
          retentionDays: 60,
          now: _now,
        ),
        isNull,
      );
    });

    test('writes again once a day has passed', () {
      expect(
        refreshedArtifactExpiry(
          data: {
            'expiresAt': Timestamp.fromDate(_now),
            'lastPlayedAt': Timestamp.fromDate(
              _now.subtract(const Duration(days: 1, minutes: 1)),
            ),
          },
          retentionDays: 60,
          now: _now,
        ),
        isNotNull,
      );
    });

    test('reads the play record however it was written', () {
      expect(
        artifactLastPlayedAt({'lastPlayedAt': Timestamp.fromDate(_now)}),
        _now,
      );
      expect(
        artifactLastPlayedAt({'lastPlayedAt': _now.toIso8601String()}),
        _now,
      );
      expect(artifactLastPlayedAt({'lastPlayedAt': 17}), isNull);
      expect(artifactLastPlayedAt(null), isNull);
    });
  });
}

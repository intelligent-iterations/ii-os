import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/generation_history.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/generated_editor_media.dart';

const _workspaceId = 'workspace-1';
const _bucket = 'workspace-bucket';
const _jobId = 'job-1';
const _objectName = 'workspaces/$_workspaceId/runs/$_jobId/video.mp4';
const _generation = '1';
const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('generated editor imports require exact integrity metadata', () async {
    final api = ApiClient(baseUrl: '', reportFailures: false);
    addTearDown(api.close);
    final grant = _grant();

    for (final metadata in <Map<String, Object?>>[
      {'sha256': _digest},
      {'size_bytes': 1024},
      {'size_bytes': 1.5, 'sha256': _digest},
      {'size_bytes': -1, 'sha256': _digest},
      {'size_bytes': 1024, 'sha256': 'invalid'},
    ]) {
      final entry = _entry(metadata: metadata);

      await expectLater(
        downloadGeneratedEditorMedia(
          api: api,
          grant: grant,
          entry: entry,
          workspaceId: _workspaceId,
          expectedBucket: _bucket,
        ),
        throwsFormatException,
      );
    }
  });

  test('generated editor import is bound to its workspace grant', () async {
    final api = ApiClient(baseUrl: '', reportFailures: false);
    addTearDown(api.close);
    final entry = _entry(metadata: {'size_bytes': 1024, 'sha256': _digest});
    final validGrant = _grant();
    final validUri = Uri.parse(validGrant.url);
    final expiryMismatchUrl = validUri
        .replace(
          queryParameters: {
            ...validUri.queryParameters,
            'X-Goog-Expires': '301',
          },
        )
        .toString();

    for (final grant in [
      _grant(workspaceId: 'workspace-2'),
      _grant(jobId: 'job-2'),
      _grant(bucket: 'other-workspace-bucket'),
      _grant(objectName: 'workspaces/$_workspaceId/runs/$_jobId/other.mp4'),
      _grant(generation: '2'),
      _grant(sizeBytes: 2048),
      _grant(sha256: List<String>.filled(64, 'b').join()),
      _grant(contentType: 'video/webm'),
      _grant(
        url:
            'https://other-workspace-bucket.storage.googleapis.com/'
            '$_objectName?generation=$_generation',
      ),
      _grant(
        url:
            'https://$_bucket.storage.googleapis.com/'
            'workspaces/$_workspaceId/runs/$_jobId/other.mp4'
            '?generation=$_generation',
      ),
      _grant(url: 'https://$_bucket.storage.googleapis.com/$_objectName'),
      _grant(url: expiryMismatchUrl, expiresAt: validGrant.expiresAt),
      _grant(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      ),
    ]) {
      await expectLater(
        downloadGeneratedEditorMedia(
          api: api,
          grant: grant,
          entry: entry,
          workspaceId: _workspaceId,
          expectedBucket: _bucket,
        ),
        throwsFormatException,
      );
    }

    await expectLater(
      downloadGeneratedEditorMedia(
        api: api,
        grant: _grant(),
        entry: _entry(
          objectName: 'workspaces/other/runs/$_jobId/video.mp4',
          metadata: {'size_bytes': 1024, 'sha256': _digest},
        ),
        workspaceId: _workspaceId,
        expectedBucket: _bucket,
      ),
      throwsFormatException,
    );
  });
}

ArtifactReadGrant _grant({
  String? url,
  String workspaceId = _workspaceId,
  String jobId = _jobId,
  String bucket = _bucket,
  String objectName = _objectName,
  String generation = _generation,
  int sizeBytes = 1024,
  String sha256 = _digest,
  String contentType = 'video/mp4',
  DateTime? expiresAt,
}) {
  final signedAt = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  final effectiveExpiresAt =
      expiresAt ?? signedAt.add(const Duration(minutes: 5));
  return ArtifactReadGrant(
    url:
        url ??
        'https://$bucket.storage.googleapis.com/'
            '$objectName?generation=$generation'
            '&X-Goog-Algorithm=GOOG4-RSA-SHA256'
            '&X-Goog-Credential=ii-os-data%40example.com%2F'
            '${_v4Timestamp(signedAt).substring(0, 8)}%2Fauto%2Fstorage%2F'
            'goog4_request'
            '&X-Goog-Date=${_v4Timestamp(signedAt)}'
            '&X-Goog-Expires=300'
            '&X-Goog-SignedHeaders=host'
            '&X-Goog-Signature=${List.filled(512, '0').join()}',
    expiresAt: effectiveExpiresAt,
    workspaceId: workspaceId,
    jobId: jobId,
    bucket: bucket,
    objectName: objectName,
    generation: generation,
    sizeBytes: sizeBytes,
    sha256: sha256,
    contentType: contentType,
  );
}

String _v4Timestamp(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${two(value.month)}${two(value.day)}T'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
}

HistoryEntryModel _entry({
  required Map<String, Object?> metadata,
  String objectName = _objectName,
}) {
  return HistoryEntryModel.fromJobArtifact(
    job: const {'jobId': _jobId, 'status': 'completed'},
    artifact: {
      'path': objectName,
      'content_type': 'video/mp4',
      'generation': _generation,
      ...metadata,
    },
  );
}

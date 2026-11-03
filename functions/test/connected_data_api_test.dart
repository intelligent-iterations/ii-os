import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/connected_data_api.dart';
import 'package:test/test.dart';

void main() {
  test('recovers a legacy artifact identity from verified GCS metadata', () {
    final digest = List.filled(64, 'a').join();
    final recovered = recoveredArtifactMetadata(
      artifact: {
        'path': 'workspaces/w/runs/job-1/extended-frame.png',
        'generation': '42',
        'content_type': 'image/png',
      },
      remoteGeneration: '42',
      remoteContentType: 'image/png',
      remoteSizeBytes: 2048,
      remoteSha256: digest,
    );

    expect(recovered['size_bytes'], 2048);
    expect(recovered['sha256'], digest);
  });

  test('rejects GCS metadata that does not match the recorded generation', () {
    expect(
      () => recoveredArtifactMetadata(
        artifact: {
          'path': 'workspaces/w/runs/job-1/extended-frame.png',
          'generation': '42',
          'content_type': 'image/png',
        },
        remoteGeneration: '43',
        remoteContentType: 'image/png',
        remoteSizeBytes: 2048,
        remoteSha256: List.filled(64, 'b').join(),
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'asset_metadata_invalid',
        ),
      ),
    );
  });
}

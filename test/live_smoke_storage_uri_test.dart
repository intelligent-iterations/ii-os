import 'package:flutter_test/flutter_test.dart';

import '../tool/live_smoke_storage_uri.dart';

void main() {
  test('encodes a nested GCS object name exactly once', () {
    final uri = buildStorageJsonObjectUri(
      bucket: 'workspace-media',
      objectName: 'workspaces/workspace-1/ghost/job-1/preview.png',
      queryParameters: {'ifGenerationMatch': '123'},
    );

    expect(
      uri.toString(),
      'https://storage.googleapis.com/storage/v1/b/workspace-media/o/'
      'workspaces%2Fworkspace-1%2Fghost%2Fjob-1%2Fpreview.png?'
      'ifGenerationMatch=123',
    );
    expect(uri.toString(), isNot(contains('%252F')));
  });

  test('builds a generation-bound media download URI', () {
    final uri = buildStorageJsonObjectUri(
      bucket: 'workspace-media',
      objectName: 'workspaces/workspace-1/source-assets/asset-1/source.mp4',
      download: true,
      queryParameters: {'alt': 'media', 'generation': '456'},
    );

    expect(
      uri.toString(),
      'https://storage.googleapis.com/download/storage/v1/b/'
      'workspace-media/o/workspaces%2Fworkspace-1%2Fsource-assets%2Fasset-1%2F'
      'source.mp4?alt=media&generation=456',
    );
    expect(uri.toString(), isNot(contains('%252F')));
  });
}

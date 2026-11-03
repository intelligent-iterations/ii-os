import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/source_asset_service.dart';
import 'package:test/test.dart';

void main() {
  test('workspace object references stay inside the selected workspace', () {
    expect(
      sourceAssetWorkspaceObjectReferenceIsValid(
        workspaceId: 'workspace-1',
        objectName: 'workspaces/workspace-1/runs/job/image.png',
        generation: '42',
      ),
      isTrue,
    );
    for (final objectName in [
      'workspaces/workspace-2/runs/job/image.png',
      'workspaces/workspace-1/../workspace-2/image.png',
      'workspaces/workspace-1//image.png',
      'workspaces/workspace-1/image.png\nother',
    ]) {
      expect(
        sourceAssetWorkspaceObjectReferenceIsValid(
          workspaceId: 'workspace-1',
          objectName: objectName,
          generation: '42',
        ),
        isFalse,
      );
    }
    expect(
      sourceAssetWorkspaceObjectReferenceIsValid(
        workspaceId: 'workspace-1',
        objectName: 'workspaces/workspace-1/runs/job/image.png',
        generation: 'latest',
      ),
      isFalse,
    );
  });

  group('SourceAssetSpec', () {
    test('normalizes a bounded source image description', () {
      final spec = SourceAssetSpec.parse({
        'filename': r'../Motion shot (final).PNG',
        'contentType': 'image/png',
        'sizeBytes': 12345,
        'sha256': List.filled(32, 'AB').join(),
        'crc32c': _crc32c,
      });

      expect(spec.safeFilename, 'Motion-shot-final.png');
      expect(spec.contentType, 'image/png');
      expect(spec.sizeBytes, 12345);
      expect(spec.sha256, List.filled(32, 'ab').join());
    });

    test('rejects unsupported media and invalid integrity metadata', () {
      expect(
        () => SourceAssetSpec.parse({
          'filename': 'source.gif',
          'contentType': 'image/gif',
          'sizeBytes': 100,
          'sha256': List.filled(64, 'a').join(),
          'crc32c': _crc32c,
        }),
        throwsA(_apiError('invalid_source_asset')),
      );
      expect(
        () => SourceAssetSpec.parse({
          'filename': 'source.png',
          'contentType': 'image/png',
          'sizeBytes': 100,
          'sha256': 'not-a-digest',
          'crc32c': _crc32c,
        }),
        throwsA(_apiError('invalid_source_asset')),
      );
      expect(
        () => SourceAssetSpec.parse({
          'filename': 'source.png',
          'contentType': 'image/png',
          'sizeBytes': 100,
          'sha256': List.filled(64, 'a').join(),
          'crc32c': 'not-a-checksum',
        }),
        throwsA(_apiError('invalid_source_asset')),
      );
    });

    test('accepts a bounded MP4 for direct workspace upload', () {
      final spec = SourceAssetSpec.parse({
        'filename': r'../Local edit (final).mov',
        'contentType': 'video/mp4',
        'sizeBytes': 512 * 1024 * 1024,
        'sha256': List.filled(64, 'c').join(),
        'crc32c': _crc32c,
      });

      expect(spec.safeFilename, 'Local-edit-final.mp4');
      expect(spec.contentType, 'video/mp4');
      expect(spec.sizeBytes, 512 * 1024 * 1024);
    });

    test('accepts bounded source audio for direct workspace upload', () {
      final spec = SourceAssetSpec.parse({
        'filename': r'../Voice sample (clean take).WAV',
        'contentType': 'audio/wav',
        'sizeBytes': 50 * 1024 * 1024,
        'sha256': List.filled(64, 'd').join(),
        'crc32c': _crc32c,
      });

      expect(spec.safeFilename, 'Voice-sample-clean-take.wav');
      expect(spec.contentType, 'audio/wav');
      expect(spec.sizeBytes, 50 * 1024 * 1024);
    });

    test('accepts a bounded WebM browser edit', () {
      final spec = SourceAssetSpec.parse({
        'filename': 'local-edit.mp4',
        'contentType': 'video/webm',
        'sizeBytes': 512 * 1024 * 1024,
        'sha256': List.filled(64, 'd').join(),
        'crc32c': _crc32c,
      });

      expect(spec.safeFilename, 'local-edit.webm');
      expect(spec.contentType, 'video/webm');
    });

    test('rejects unsupported local edit formats', () {
      expect(
        () => SourceAssetSpec.parse({
          'filename': 'local-edit',
          'contentType': 'video/quicktime',
          'sizeBytes': 100,
          'sha256': List.filled(64, 'a').join(),
          'crc32c': _crc32c,
        }),
        throwsA(_apiError('invalid_source_asset')),
      );
    });

    test('rejects empty and oversized files', () {
      for (final size in [0, 50 * 1024 * 1024 + 1]) {
        expect(
          () => SourceAssetSpec.parse({
            'filename': 'source.webp',
            'contentType': 'image/webp',
            'sizeBytes': size,
            'sha256': List.filled(64, 'a').join(),
            'crc32c': _crc32c,
          }),
          throwsA(_apiError('invalid_source_asset')),
        );
      }
      expect(
        () => SourceAssetSpec.parse({
          'filename': 'local-edit.mp4',
          'contentType': 'video/mp4',
          'sizeBytes': 512 * 1024 * 1024 + 1,
          'sha256': List.filled(64, 'a').join(),
          'crc32c': _crc32c,
        }),
        throwsA(_apiError('invalid_source_asset')),
      );
    });
  });
}

const _crc32c = '4waSgw==';

Matcher _apiError(String code) =>
    isA<ApiError>().having((error) => error.code, 'code', code);

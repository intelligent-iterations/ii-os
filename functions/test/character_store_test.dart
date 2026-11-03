import 'package:ii_os_functions/src/character_store.dart';
import 'package:test/test.dart';

void main() {
  test('body and sheet selections persist in distinct fields', () {
    expect(characterSelectedImageField(body: false), 'selectedImage');
    expect(characterSelectedImageField(body: true), 'selectedBodyImage');
  });

  test('character image metadata retains its workspace for URL signing', () {
    final image = buildCharacterImageMetadata(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      path: 'workspaces/workspace-1/runs/job-1/image/sheet.png',
      generation: '42',
      contentType: 'image/png',
      sizeBytes: 2048,
      sha256: List.filled(64, 'a').join(),
      createdAt: '2026-07-16T20:00:00.000Z',
      selected: true,
    );

    expect(image['workspaceId'], 'workspace-1');
    expect(image['path'], contains('/sheet.png'));
    expect(image['selected'], isTrue);
    expect(image['sizeBytes'], 2048);
    expect(image['sha256'], List.filled(64, 'a').join());
  });

  test('source image metadata is selectable character history', () {
    final image = buildCharacterSourceImageMetadata(
      workspaceId: 'workspace-1',
      sourceAssetId: 'source-1',
      path: 'workspaces/workspace-1/source-assets/source-1/reference.png',
      generation: '7',
      contentType: 'image/png',
      sizeBytes: 1024,
      sha256: List.filled(64, 'b').join(),
      createdAt: '2026-07-19T12:00:00.000Z',
      selected: false,
    );

    expect(image['jobId'], 'source-asset:source-1');
    expect(characterSourceImageJobId('source-1'), image['jobId']);
    expect(image['sourceImage'], isTrue);
    expect(image['selected'], isFalse);
  });

  test('character edit history receives a concise descriptive label', () {
    expect(
      characterImageEditLabel({
        'generationReview': {'kind': 'character_sheet_edit', 'mode': 'area'},
        'inputs': {
          'prompt':
              'Make the white patch on the cat chest smaller and consistent.',
        },
      }),
      'Area edit: Make the white patch on the cat\u2026',
    );
    expect(
      characterImageEditLabel({
        'generationReview': {
          'kind': 'character_sheet_edit',
          'mode': 'wholeSheet',
        },
        'inputs': {'prompt': 'Clean up the line work.'},
      }),
      'Sheet tweak: Clean up the line work',
    );
    expect(characterImageEditLabel({'kind': 'image-create'}), isNull);
  });
}

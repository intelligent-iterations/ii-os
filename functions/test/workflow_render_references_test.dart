import 'dart:convert';

import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workflow_source_references.dart';
import 'package:test/test.dart';

String _render({int version = 1, List<Map<String, Object?>>? inputs}) =>
    jsonEncode({
      'version': version,
      'arguments': ['-i', 'input-0.mp4'],
      'outputName': 'output.mp4',
      'inputs':
          inputs ??
          [
            {'name': 'input-0.mp4', 'assetId': 'asset-1', 'byteLength': 64},
            {'name': 'input-1.m4a', 'assetId': 'asset-2', 'byteLength': 32},
          ],
    });

void main() {
  test('a render names every file it reads, in order', () {
    final references = workflowSourceReferences({'render_manifest': _render()});

    expect(references, hasLength(2));
    expect(references[0].assetId, 'asset-1');
    expect(references[0].role, 'input-0.mp4');
    expect(references[0].ordinal, 0);
    expect(references[1].assetId, 'asset-2');
    expect(references[1].role, 'input-1.m4a');
    expect(references[1].ordinal, 1);
    expect(references[0].inputField, workflowRenderManifestInput);
  });

  test('a render is refused alongside other reference inputs', () {
    expect(
      () => workflowSourceReferences({
        'render_manifest': _render(),
        'source_asset_id': 'asset-9',
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('a render described by another version is refused', () {
    expect(
      () => workflowSourceReferences({'render_manifest': _render(version: 2)}),
      throwsA(isA<ApiError>()),
    );
  });

  test('a render that reads nothing is refused', () {
    expect(
      () => workflowSourceReferences({'render_manifest': _render(inputs: [])}),
      throwsA(isA<ApiError>()),
    );
  });

  test('a render that reads more than a runner will fetch is refused', () {
    expect(
      () => workflowSourceReferences({
        'render_manifest': _render(
          inputs: [
            for (var index = 0; index <= workflowMaxRenderInputs; index++)
              {'name': 'input-$index.mp4', 'assetId': 'asset-$index'},
          ],
        ),
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('an input named anything but a render input is refused', () {
    for (final name in [
      '../escape.mp4',
      'input-0',
      'inputs/input-0.mp4',
      'input-000.mp4',
      'input-0.MP4',
      '',
    ]) {
      expect(
        () => workflowSourceReferences({
          'render_manifest': _render(
            inputs: [
              {'name': name, 'assetId': 'asset-1'},
            ],
          ),
        }),
        throwsA(isA<ApiError>()),
        reason: name,
      );
    }
  });

  test('the same input named twice is refused', () {
    expect(
      () => workflowSourceReferences({
        'render_manifest': _render(
          inputs: [
            {'name': 'input-0.mp4', 'assetId': 'asset-1'},
            {'name': 'input-0.mp4', 'assetId': 'asset-2'},
          ],
        ),
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('an input with no stored media is refused', () {
    expect(
      () => workflowSourceReferences({
        'render_manifest': _render(
          inputs: [
            {'name': 'input-0.mp4', 'assetId': ''},
          ],
        ),
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('a render that is not bounded JSON is refused', () {
    expect(
      () => workflowSourceReferences({'render_manifest': 'not json'}),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => workflowSourceReferences({
        'render_manifest': 'x' * (workflowRenderManifestLimit + 1),
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('inputs with no render are left to the paths that already exist', () {
    expect(workflowSourceReferences(const {'render_manifest': ''}), isEmpty);
    expect(
      workflowSourceReferences(const {'source_asset_id': 'asset-1'}),
      hasLength(1),
    );
  });
}

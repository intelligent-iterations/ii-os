import 'dart:convert';

import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workflow_source_references.dart';
import 'package:test/test.dart';

const _videoId = '33449737-9e39-4d53-8040-f39d5f7bc3ce';
const _imageId = 'e4a443e5-ef0d-4f23-b977-2d89959a0812';
const _videoReferenceId = '724140ee-aa03-459a-a463-4527bdaf445a';

void main() {
  test('keeps legacy source inputs in their declared order', () {
    final references = workflowSourceReferences(const {
      'source_asset_id': _imageId,
      'voice_reference_asset_id': _videoId,
    });

    expect(references.map((item) => item.assetId), [_imageId, _videoId]);
    expect(references.last.kind, 'audio');
    expect(references.last.role, 'audio_reference');
  });

  test('parses a bounded role-aware video edit manifest', () {
    final references = workflowSourceReferences({
      'generation_mode': 'video_edit',
      'reference_manifest': jsonEncode({
        'schema_version': 1,
        'mode': 'video_edit',
        'references': [
          {
            'asset_id': _videoId,
            'kind': 'video',
            'role': 'source_video',
            'ordinal': 0,
          },
          {
            'asset_id': _imageId,
            'kind': 'image',
            'role': 'subject',
            'ordinal': 1,
          },
        ],
        'edit_operation': 'character_replacement',
        'identity_replacement_consent': true,
      }),
    });

    expect(references, hasLength(2));
    expect(references.first.kind, 'video');
    expect(references.first.role, 'source_video');
    expect(references.first.ordinal, 0);
    expect(references.last.role, 'subject');
  });

  test('requires endpoint roles and matching generation mode', () {
    for (final input in [
      {
        'generation_mode': 'first_frame_to_video',
        'reference_manifest': _manifest(
          mode: 'first_frame_to_video',
          references: const [],
        ),
      },
      {
        'generation_mode': 'last_frame_to_video',
        'reference_manifest': _manifest(
          mode: 'first_frame_to_video',
          references: const [],
        ),
      },
    ]) {
      expect(
        () => workflowSourceReferences(input),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'invalid_reference_manifest',
          ),
        ),
      );
    }
  });

  test('rejects character replacement without affirmative consent', () {
    expect(
      () => workflowSourceReferences({
        'generation_mode': 'video_edit',
        'reference_manifest': jsonEncode({
          'schema_version': 1,
          'mode': 'video_edit',
          'references': [
            {
              'asset_id': _videoId,
              'kind': 'video',
              'role': 'source_video',
              'ordinal': 0,
            },
          ],
          'edit_operation': 'character_replacement',
          'identity_replacement_consent': false,
        }),
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.message,
          'message',
          contains('permission'),
        ),
      ),
    );
  });

  test('rejects duplicate asset identities and kind-role mismatches', () {
    expect(
      () => workflowSourceReferences({
        'generation_mode': 'first_last_frame_to_video',
        'reference_manifest': _manifest(
          mode: 'first_last_frame_to_video',
          references: const [
            {
              'asset_id': _imageId,
              'kind': 'image',
              'role': 'first_frame',
              'ordinal': 0,
            },
            {
              'asset_id': _imageId,
              'kind': 'video',
              'role': 'last_frame',
              'ordinal': 1,
            },
          ],
        ),
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('accepts multimodal continuation only with one source video', () {
    final references = workflowSourceReferences({
      'generation_mode': 'video_continue',
      'reference_manifest': _manifest(
        mode: 'video_continue',
        references: const [
          {
            'asset_id': _videoId,
            'kind': 'video',
            'role': 'source_video',
            'ordinal': 0,
          },
          {
            'asset_id': _imageId,
            'kind': 'image',
            'role': 'pose_reference',
            'ordinal': 1,
          },
          {
            'asset_id': _videoReferenceId,
            'kind': 'video',
            'role': 'video_style',
            'ordinal': 2,
          },
        ],
      ),
    });
    expect(references.map((item) => item.role), [
      'source_video',
      'pose_reference',
      'video_style',
    ]);

    expect(
      () => workflowSourceReferences({
        'generation_mode': 'video_continue',
        'reference_manifest': _manifest(
          mode: 'video_continue',
          references: const [],
        ),
      }),
      throwsA(isA<ApiError>()),
    );
  });
}

String _manifest({
  required String mode,
  required List<Map<String, Object?>> references,
}) => jsonEncode({'schema_version': 1, 'mode': mode, 'references': references});

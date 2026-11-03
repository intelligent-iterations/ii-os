import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/image_edit_selection.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/view_models/image_edit_submission_view_model.dart';

final class _Jobs implements JobRepository {
  final submissions = <JobSubmission>[];

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async {
    submissions.add(submission);
    return {'id': 'job-${submissions.length}'};
  }

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) =>
      throw UnimplementedError();

  @override
  Future<JobListing> list(String workspaceId) => throw UnimplementedError();
}

final class _Assets implements SourceAssetRepository {
  final filenames = <String>[];

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async {
    filenames.add(filename);
    return 'asset-${filenames.length}';
  }
}

WorkflowTemplateModel _target() => const WorkflowTemplateModel(
  id: 'qwen-edit',
  workflowId: 'image-edit-qwen-2511',
  version: '2',
  displayName: 'Qwen',
  model: 'qwen-image-edit-2511',
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
  inputs: {
    'mode': WorkflowInputModel(type: 'string', required: true),
    'source_asset_id': WorkflowInputModel(type: 'string', required: true),
    'source_asset_id_2': WorkflowInputModel(type: 'string', required: false),
    'source_asset_id_3': WorkflowInputModel(type: 'string', required: false),
    'prompt': WorkflowInputModel(type: 'string', required: true),
    'seed': WorkflowInputModel(type: 'number', required: false),
  },
);

void main() {
  test('uploads ordered references and submits only declared inputs', () async {
    final jobs = _Jobs();
    final assets = _Assets();
    final viewModel = ImageEditSubmissionViewModel(jobs, assets);

    final outcome = await viewModel.submit(
      ImageEditSubmissionRequest(
        workspaceId: 'workspace',
        expectedBucket: 'bucket',
        mode: ImageEditMode.revision,
        targets: [_target()],
        prompt: 'Use the subject from A, style from B, and setting from C.',
        seedText: '42',
        sourceFilename: 'a.png',
        sourceBytes: Uint8List.fromList([1]),
        sourceContentType: 'image/png',
        sourceAssetId: null,
        referenceFilenames: const ['b.png', 'c.png'],
        referenceBytes: [
          Uint8List.fromList([2]),
          Uint8List.fromList([3]),
        ],
        referenceContentTypes: const ['image/png', 'image/png'],
        referenceAssetIds: const [null, null],
        maskRegions: const <Rect>[],
        controlStrength: 0.75,
        ghostMode: false,
        keptEnhancedText: false,
      ),
    );

    expect(assets.filenames, ['a.png', 'b.png', 'c.png']);
    expect(outcome.referenceAssetIds, ['asset-2', 'asset-3']);
    expect(jobs.submissions.single.input, {
      'mode': 'edit',
      'source_asset_id': 'asset-1',
      'source_asset_id_2': 'asset-2',
      'source_asset_id_3': 'asset-3',
      'prompt': 'Use the subject from A, style from B, and setting from C.',
      'seed': 42,
    });
  });

  test('rejects a gap in ordered references before uploading it', () async {
    final assets = _Assets();
    final viewModel = ImageEditSubmissionViewModel(_Jobs(), assets);

    expect(
      () => viewModel.submit(
        ImageEditSubmissionRequest(
          workspaceId: 'workspace',
          expectedBucket: 'bucket',
          mode: ImageEditMode.revision,
          targets: [_target()],
          prompt: 'Use C.',
          seedText: '',
          sourceFilename: 'a.png',
          sourceBytes: Uint8List.fromList([1]),
          sourceContentType: 'image/png',
          sourceAssetId: 'asset-a',
          referenceFilenames: const [null, 'c.png'],
          referenceBytes: [
            null,
            Uint8List.fromList([3]),
          ],
          referenceContentTypes: const [null, 'image/png'],
          referenceAssetIds: const [null, null],
          maskRegions: const [],
          controlStrength: 0.75,
          ghostMode: false,
          keptEnhancedText: false,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(assets.filenames, isEmpty);
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/image_edit_selection.dart';
import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../repositories/source_asset_repository.dart';

final class ImageEditSubmissionRequest {
  const ImageEditSubmissionRequest({
    required this.workspaceId,
    required this.expectedBucket,
    required this.mode,
    required this.targets,
    required this.prompt,
    required this.seedText,
    required this.sourceFilename,
    required this.sourceBytes,
    required this.sourceContentType,
    required this.sourceAssetId,
    required this.referenceFilenames,
    required this.referenceBytes,
    required this.referenceContentTypes,
    required this.referenceAssetIds,
    required this.maskRegions,
    required this.controlStrength,
    required this.ghostMode,
    required this.keptEnhancedText,
  });

  final String workspaceId;
  final String expectedBucket;
  final ImageEditMode mode;
  final List<WorkflowTemplateModel> targets;
  final String prompt;
  final String seedText;
  final String? sourceFilename;
  final Uint8List? sourceBytes;
  final String? sourceContentType;
  final String? sourceAssetId;
  final List<String?> referenceFilenames;
  final List<Uint8List?> referenceBytes;
  final List<String?> referenceContentTypes;
  final List<String?> referenceAssetIds;
  final List<Rect> maskRegions;
  final double controlStrength;
  final bool ghostMode;
  final bool keptEnhancedText;
}

final class ImageEditSubmissionOutcome {
  const ImageEditSubmissionOutcome({
    required this.sourceAssetId,
    required this.referenceAssetIds,
    required this.effectiveSeed,
    required this.submissions,
  });

  final String sourceAssetId;
  final List<String?> referenceAssetIds;
  final int? effectiveSeed;
  final List<ImageEditSubmission> submissions;
}

/// Testable owner of upload ordering and per-workflow image-edit inputs.
final class ImageEditSubmissionViewModel {
  const ImageEditSubmissionViewModel(this._jobs, this._sourceAssets);

  final JobRepository _jobs;
  final SourceAssetRepository _sourceAssets;

  Future<ImageEditSubmissionOutcome> submit(
    ImageEditSubmissionRequest request, {
    void Function(String label)? onPhase,
  }) async {
    final seed = _validatedSeed(request);
    final sourceAssetId = await _sourceAsset(request, onPhase: onPhase);
    final references = request.mode == ImageEditMode.revision
        ? await _referenceAssets(request, onPhase: onPhase)
        : List<String?>.from(request.referenceAssetIds);
    final effectiveSeed =
        seed ??
        (request.targets.length > 1
            ? DateTime.now().microsecondsSinceEpoch % 2147483647
            : null);
    onPhase?.call(
      request.targets.length == 1
          ? 'Launching job'
          : 'Launching ${request.targets.length} jobs',
    );
    final submissions = await Future.wait([
      for (final target in request.targets)
        _submitTarget(
          request,
          target: target,
          sourceAssetId: sourceAssetId,
          referenceAssetIds: references.whereType<String>().toList(),
          effectiveSeed: effectiveSeed,
        ),
    ]);
    return ImageEditSubmissionOutcome(
      sourceAssetId: sourceAssetId,
      referenceAssetIds: references,
      effectiveSeed: effectiveSeed,
      submissions: submissions,
    );
  }

  int? _validatedSeed(ImageEditSubmissionRequest request) {
    if (request.prompt.trim().isEmpty ||
        request.sourceFilename == null ||
        request.sourceBytes == null ||
        request.sourceContentType == null) {
      throw const FormatException(
        'A source image and instruction are required.',
      );
    }
    if (request.mode == ImageEditMode.inpaint && request.maskRegions.isEmpty) {
      throw const FormatException('Select an edit area.');
    }
    if (request.targets.isEmpty) {
      throw const FormatException('No enabled image-edit model is available.');
    }
    final text = request.seedText.trim();
    final seed = text.isEmpty ? null : int.tryParse(text);
    if (text.isNotEmpty && seed == null) {
      throw const FormatException('Seed must be a number.');
    }
    return seed;
  }

  Future<String> _sourceAsset(
    ImageEditSubmissionRequest request, {
    required void Function(String label)? onPhase,
  }) async {
    if (request.sourceAssetId case final existing?) return existing;
    onPhase?.call('Uploading source');
    return _sourceAssets.upload(
      workspaceId: request.workspaceId,
      expectedBucket: request.expectedBucket,
      filename: request.sourceFilename!,
      bytes: request.sourceBytes!,
      contentType: request.sourceContentType!,
      ghostMode: request.ghostMode,
    );
  }

  Future<List<String?>> _referenceAssets(
    ImageEditSubmissionRequest request, {
    required void Function(String label)? onPhase,
  }) async {
    final limit = maximumImageEditReferenceSlots(request.targets);
    final selected = request.referenceFilenames.take(limit).toList();
    final last = selected.lastIndexWhere((filename) => filename != null);
    final result = List<String?>.from(request.referenceAssetIds);
    if (last < 0) return result;
    if (selected.take(last + 1).any((filename) => filename == null)) {
      throw const FormatException(
        'Add reference images in order, starting with image B.',
      );
    }
    for (var index = 0; index <= last; index++) {
      if (result[index] != null) continue;
      final filename = request.referenceFilenames[index];
      final bytes = request.referenceBytes[index];
      final contentType = request.referenceContentTypes[index];
      if (filename == null || bytes == null || contentType == null) {
        throw const FormatException('Choose a valid reference image.');
      }
      onPhase?.call('Uploading image ${String.fromCharCode(66 + index)}');
      result[index] = await _sourceAssets.upload(
        workspaceId: request.workspaceId,
        expectedBucket: request.expectedBucket,
        filename: filename,
        bytes: bytes,
        contentType: contentType,
        ghostMode: request.ghostMode,
      );
    }
    return result;
  }

  Future<ImageEditSubmission> _submitTarget(
    ImageEditSubmissionRequest request, {
    required WorkflowTemplateModel target,
    required String sourceAssetId,
    required List<String> referenceAssetIds,
    required int? effectiveSeed,
  }) async {
    final baseInput = <String, Object?>{
      'mode': request.mode == ImageEditMode.inpaint ? 'inpaint' : 'edit',
      'source_asset_id': sourceAssetId,
      'prompt': request.prompt.trim(),
      'control_strength': request.controlStrength,
      'seed': ?effectiveSeed,
      if (request.mode == ImageEditMode.inpaint) ...{
        'mask_x': request.maskRegions.first.left,
        'mask_y': request.maskRegions.first.top,
        'mask_width': request.maskRegions.first.width,
        'mask_height': request.maskRegions.first.height,
      },
    };
    try {
      final response = await _jobs.submit(
        request.workspaceId,
        JobSubmission(
          workflowKey: target.id,
          pageSlug: 'image-edit',
          ghostMode: request.ghostMode,
          keptEnhancedText: request.keptEnhancedText,
          input: imageEditInputForTarget(
            target: target,
            baseInput: baseInput,
            referenceAssetIds: referenceAssetIds,
            maskRegions: request.maskRegions,
          ),
        ),
      );
      return ImageEditSubmission.success(template: target, response: response);
    } on Object catch (error) {
      return ImageEditSubmission.failure(template: target, failure: error);
    }
  }
}

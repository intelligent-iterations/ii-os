part of 'video_generation_view_model.dart';

extension VideoGenerationSubmission on VideoGenerationViewModel {
  Future<JsonMap?> submit({required String prompt}) async {
    final trimmedPrompt = prompt.trim();
    if (!_submissionIsValid(trimmedPrompt)) return null;
    final template = selectedTemplate!;
    final durationSeconds = isSeedVr2 ? null : _validatedDurationSeconds();
    if (!isSeedVr2 && durationSeconds == null) return null;

    submittedJob = null;
    busyLabel = _submissionBusyLabel;
    setBusyForObject(VideoGenerationBusy.submit, true);
    setError(null);
    try {
      final input = await _submissionInput(trimmedPrompt, durationSeconds);
      await _appendH3Inputs(input);
      final submission = JobSubmission(
        keptEnhancedText: keptEnhancedText,
        workflowKey: template.id,
        pageSlug: 'video-generation',
        ghostMode: ghostMode,
        input: input,
      );
      submittedJob = await _jobs.submit(workspaceId, submission);
      _lastSubmission = submission;
      await _onSubmitted?.call();
      return submittedJob;
    } on Object catch (error) {
      setError(error);
      return null;
    } finally {
      busyLabel = 'Launch job';
      setBusyForObject(VideoGenerationBusy.submit, false);
    }
  }

  bool _submissionIsValid(String prompt) {
    if (!isSeedVr2 && prompt.isEmpty) {
      setError(const FormatException('A video prompt is required.'));
      return false;
    }
    if (isMiniMaxH3 && prompt.length > 7000) {
      setError(
        const FormatException(
          'MiniMax H3 prompts are limited to 7,000 characters.',
        ),
      );
      return false;
    }
    if (sourceImageRequired &&
        (sourceBytes == null ||
            sourceFilename == null ||
            sourceContentType == null)) {
      setError(
        const FormatException(
          'A source image and prompt are required for LTX.',
        ),
      );
      return false;
    }
    if (sourceVideoRequired &&
        (sourceBytes == null ||
            sourceFilename == null ||
            sourceContentType?.startsWith('video/') != true)) {
      setError(
        const FormatException('A valid source video is required for SeedVR2.'),
      );
      return false;
    }
    if (isMiniMaxH3 && !_validateH3References()) return false;
    if (selectedTemplate?.enabled != true) {
      setError(
        const FormatException('No enabled video workflow is available.'),
      );
      return false;
    }
    return true;
  }

  String get _submissionBusyLabel =>
      (sourceImageRequired || sourceVideoRequired) && sourceAssetId == null
      ? 'Uploading source'
      : isMiniMaxH3 && h3References.any((item) => item.assetId == null)
      ? 'Uploading references'
      : 'Launching job';

  Future<JsonMap> _submissionInput(String prompt, int? durationSeconds) async {
    if (isSeedVr2) {
      return {
        'source_asset_id': sourceAssetId ?? await _uploadSource(),
        'target_resolution': 1080,
        'quality_preset': 'quality',
        'preserve_audio': true,
        'seed': 42,
      };
    }
    final input = <String, Object?>{
      'prompt': prompt,
      'duration_seconds': durationSeconds,
      'orientation': orientation,
      'fps': isMiniMaxH3 ? 24 : fps,
    };
    if (sourceImageRequired) {
      input['source_asset_id'] = sourceAssetId ?? await _uploadSource();
      busyLabel = 'Launching job';
      notifyListeners();
    }
    return input;
  }
}

extension VideoGenerationSubmissionRetry on VideoGenerationViewModel {
  Future<void> retryLastSubmission() async {
    final submission = _lastSubmission;
    if (submission == null) {
      throw StateError('This generation no longer has retryable inputs.');
    }
    if (submitting) {
      throw StateError('This generation is already being retried.');
    }
    busyLabel = 'Launching job';
    setBusyForObject(VideoGenerationBusy.submit, true);
    setError(null);
    try {
      submittedJob = await _jobs.submit(workspaceId, submission);
      await _onSubmitted?.call();
    } on Object catch (error) {
      setError(error);
      rethrow;
    } finally {
      busyLabel = 'Launch job';
      setBusyForObject(VideoGenerationBusy.submit, false);
    }
  }
}

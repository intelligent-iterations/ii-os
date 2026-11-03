part of 'video_editor_projects_view_model.dart';

sealed class VideoProjectOpenResult {
  const VideoProjectOpenResult();
}

/// One fully prepared project that has already been committed atomically.
final class VideoProjectOpened extends VideoProjectOpenResult {
  const VideoProjectOpened({
    required this.project,
    required this.timeline,
    required this.media,
  });

  final VideoProject project;
  final EditorProject? timeline;
  final List<LocalEditorMedia> media;
}

enum VideoProjectOpenRejection {
  alreadyOpening,
  anotherOperation,
  projectUnavailable,
  mediaUnavailable,
  timelineMalformed,
  timelineLegacyUnsupported,
  timelineNewerBuildRequired,
  timelineInvalid,
}

/// A rejected request. The formerly open project remains authoritative.
final class VideoProjectOpenRejected extends VideoProjectOpenResult {
  const VideoProjectOpenRejected(this.reason);

  final VideoProjectOpenRejection reason;
}

final class _VideoProjectMediaOpenFailure implements Exception {
  const _VideoProjectMediaOpenFailure(this.message);

  final String message;
}

extension VideoEditorProjectOpen on VideoEditorProjectsViewModel {
  Future<VideoProjectOpenResult> openProject(String projectId) async {
    if (isOpening) {
      return const VideoProjectOpenRejected(
        VideoProjectOpenRejection.alreadyOpening,
      );
    }
    if (isSaving || isDeleting || isDispatching || isPersistingRender) {
      return const VideoProjectOpenRejected(
        VideoProjectOpenRejection.anotherOperation,
      );
    }
    final openAtStart = _open;
    final renderGenerationAtStart = _renderJobGeneration;
    _failure = null;
    setBusyForObject(VideoProjectBusy.open, true);
    try {
      final project = await _projects.read(workspaceId, projectId);
      if (project.isBlank) {
        if (project.media.isNotEmpty) {
          throw const EditorTimelineSchemaFailure.malformed();
        }
        return _commitOpenedProject(
          project: project,
          timeline: null,
          media: const [],
          openAtStart: openAtStart,
          renderGenerationAtStart: renderGenerationAtStart,
        );
      }
      final prepared = prepareEditorTimeline(project.timeline);
      validateEditorTimelineWithoutMedia(prepared.timeline);
      _verifyStoredMediaRecords(prepared, project);
      final media = await _restoreProjectMedia(project);
      final timeline = decodeEditorTimeline(
        prepared.timeline,
        sources: {for (final item in media) item.id: item.source},
      );
      return _commitOpenedProject(
        project: project,
        timeline: timeline,
        media: media,
        openAtStart: openAtStart,
        renderGenerationAtStart: renderGenerationAtStart,
      );
    } on _VideoProjectMediaOpenFailure catch (failure) {
      _failure = failure.message;
      return const VideoProjectOpenRejected(
        VideoProjectOpenRejection.mediaUnavailable,
      );
    } on EditorTimelineSchemaFailure catch (failure) {
      _failure = failure.message;
      return VideoProjectOpenRejected(_schemaRejection(failure.kind));
    } on EditorTimelineDecodeFailure catch (failure) {
      _failure = failure.message;
      final schemaKind = failure.schemaFailureKind;
      return VideoProjectOpenRejected(
        schemaKind != null
            ? _schemaRejection(schemaKind)
            : failure.missingMediaIds.isEmpty
            ? VideoProjectOpenRejection.timelineInvalid
            : VideoProjectOpenRejection.mediaUnavailable,
      );
    } on Object {
      _failure = 'That project could not be opened.';
      return const VideoProjectOpenRejected(
        VideoProjectOpenRejection.projectUnavailable,
      );
    } finally {
      setBusyForObject(VideoProjectBusy.open, false);
    }
  }

  void _verifyStoredMediaRecords(
    PreparedEditorTimeline prepared,
    VideoProject project,
  ) {
    final storedMediaIds = project.media.map((item) => item.id).toSet();
    final missing = prepared.mediaIds
        .where((id) => !storedMediaIds.contains(id))
        .toList(growable: false);
    if (missing.isEmpty) return;
    throw EditorTimelineDecodeFailure(
      'Some of this project\u2019s media is no longer in the workspace.',
      missingMediaIds: missing,
    );
  }

  Future<List<LocalEditorMedia>> _restoreProjectMedia(
    VideoProject project,
  ) async {
    try {
      return await _mediaGateway.restore(
        workspaceId: workspaceId,
        expectedBucket: expectedBucket,
        media: project.media,
      );
    } on VideoProjectMediaMissing catch (missing) {
      throw _VideoProjectMediaOpenFailure(
        '${missing.filename} is no longer in this workspace, so this '
        'project cannot be opened.',
      );
    } on Object {
      throw const _VideoProjectMediaOpenFailure(
        'This project\u2019s media could not be restored.',
      );
    }
  }

  VideoProjectOpenResult _commitOpenedProject({
    required VideoProject project,
    required EditorProject? timeline,
    required List<LocalEditorMedia> media,
    required VideoProject? openAtStart,
    required int renderGenerationAtStart,
  }) {
    if (openAtStart?.id == project.id &&
        (!identical(_open, openAtStart) ||
            _renderJobGeneration != renderGenerationAtStart)) {
      _failure = 'This project changed while it was being opened.';
      return const VideoProjectOpenRejected(
        VideoProjectOpenRejection.anotherOperation,
      );
    }
    _renderWatcher.stop();
    _open = project;
    _adoptRenderJob(project.summary.renderJobId);
    _failure = null;
    _adoptTimeline(timeline);
    return VideoProjectOpened(
      project: project,
      timeline: timeline,
      media: List.unmodifiable(media),
    );
  }
}

VideoProjectOpenRejection _schemaRejection(
  EditorTimelineSchemaFailureKind kind,
) => switch (kind) {
  EditorTimelineSchemaFailureKind.malformed =>
    VideoProjectOpenRejection.timelineMalformed,
  EditorTimelineSchemaFailureKind.unsupportedLegacy =>
    VideoProjectOpenRejection.timelineLegacyUnsupported,
  EditorTimelineSchemaFailureKind.newerBuildRequired =>
    VideoProjectOpenRejection.timelineNewerBuildRequired,
};

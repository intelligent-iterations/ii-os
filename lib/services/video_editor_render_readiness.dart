import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

/// The user action whose side effects must wait for structural preflight.
enum VideoEditorRenderIntent { edit, save, localRender, workspaceRender }

/// Applies one exact ii-os render target to every structural decision.
///
/// Inspection is pure: it opens no source, rasterizes no caption, creates no
/// project, and dispatches no job. Those effects belong after a successful
/// result at each action boundary.
final class VideoEditorRenderReadinessService {
  const VideoEditorRenderReadinessService({required this.compiler});

  final EditorCompositionCompiler compiler;

  EditorRenderFeasibility inspect(EditorProject project) =>
      compiler.preflight(project);

  String? failureFor(
    EditorRenderFeasibility feasibility, {
    required VideoEditorRenderIntent intent,
  }) {
    if (feasibility.issues case [final first, ...]) {
      return '${_intentPrefix(intent)} ${messageForIssue(first, intent: intent)}';
    }
    return null;
  }

  /// Stable recovery copy for a typed package issue.
  ///
  /// Package messages can contain source or lane identifiers. The host maps
  /// the type instead so UI errors never reveal those identifiers or provider
  /// implementation details.
  String messageForIssue(
    EditorRenderIssue issue, {
    required VideoEditorRenderIntent intent,
  }) => switch (issue.code) {
    EditorRenderIssueCode.invalidProject =>
      'This timeline cannot be used as it is. Shorten it, undo the most '
          'recent edit, or start a new project with the same media.',
    EditorRenderIssueCode.unsupportedSourceUse =>
      'Move the affected source to a compatible video or audio lane.',
    EditorRenderIssueCode.conflictingSourceIdentity =>
      'Remove one of the duplicated sources and import it again.',
    EditorRenderIssueCode.incompatibleSourceUse =>
      'Use separate imported copies when one source needs incompatible roles.',
    EditorRenderIssueCode.unsupportedOutputProfile =>
      'Choose another export format.',
    EditorRenderIssueCode.videoBitrateExceeded =>
      'Lower the video quality setting.',
    EditorRenderIssueCode.audioBitrateExceeded =>
      'Lower the audio quality setting.',
    EditorRenderIssueCode.emittedLayerLimitExceeded =>
      'This edit contains ${_count(issue.actual)} clip and caption segments, '
          'but this device can prepare ${_count(issue.maximum)}. Remove or '
          'combine some clips or captions.',
    EditorRenderIssueCode.inputLimitExceeded =>
      'This edit uses ${_count(issue.actual)} imported items and captions, '
          'but this device can prepare ${_count(issue.maximum)}. Reuse or '
          'remove some media and captions.',
    EditorRenderIssueCode.sourceByteLengthExceeded =>
      'One media file is too large. Trim or compress it before importing it '
          'again.',
    EditorRenderIssueCode.declaredInputBytesExceeded =>
      'The combined media files are too large. Remove, trim, or compress '
          'some media.',
    EditorRenderIssueCode.preparedInputBytesExceeded =>
      'The media and captions together need too much preparation space. '
          'Remove, trim, or compress some media, or remove some captions.',
    EditorRenderIssueCode.estimatedOutputBytesExceeded =>
      'The estimated video file is too large. Lower the quality setting or '
          'shorten the timeline.',
    EditorRenderIssueCode.captionPixelLimitExceeded =>
      'One caption is too large to prepare. Shorten it or reduce its visual '
          'size.',
    EditorRenderIssueCode.captionTotalPixelLimitExceeded =>
      'The captions are too large in total. Shorten, resize, or remove some '
          'captions.',
  };

  String _intentPrefix(VideoEditorRenderIntent intent) => switch (intent) {
    VideoEditorRenderIntent.edit =>
      'This edit is too large for the current device or workspace machine.',
    VideoEditorRenderIntent.save => 'This project cannot be saved yet.',
    VideoEditorRenderIntent.localRender =>
      'This video cannot be rendered on this device yet.',
    VideoEditorRenderIntent.workspaceRender =>
      'This video cannot be sent to a workspace machine yet.',
  };

  String _count(int? value) => value?.toString() ?? 'too many';
}

part of 'composition_compiler.dart';

/// One immutable set of editor, media, and engine limits for a render target.
@immutable
final class EditorRenderTarget {
  const EditorRenderTarget({
    this.editorLimits = const EditorLimits(),
    this.mediaLimits = const MediaLimits(),
    this.safety = const FfmpegSafetyPolicy(),
  });

  final EditorLimits editorLimits;
  final MediaLimits mediaLimits;
  final FfmpegSafetyPolicy safety;

  int get maxSourceBytes =>
      math.min(mediaLimits.maxSourceBytes, safety.maxInputBytes);

  int get maxInputBytes =>
      math.min(mediaLimits.maxInputBytes, safety.maxTotalInputBytes);

  int get maxDeclaredMediaBytes =>
      math.min(mediaLimits.declaredMediaByteLimit, maxInputBytes);

  int get maxOutputBytes => math.min(
    mediaLimits.maxOutputBytes,
    math.min(safety.maxOutputBytes, safety.maxTotalOutputBytes),
  );

  int get maxEstimatedOutputBytes =>
      math.min(mediaLimits.estimatedOutputByteLimit, maxOutputBytes);

  EditorRenderTarget withOverrides({
    MediaLimits? mediaLimits,
    FfmpegSafetyPolicy? safety,
  }) => mediaLimits == null && safety == null
      ? this
      : EditorRenderTarget(
          editorLimits: editorLimits,
          mediaLimits: mediaLimits ?? this.mediaLimits,
          safety: safety ?? this.safety,
        );

  /// Fails as caller configuration before a project is inspected.
  void validate() {
    editorLimits.validateSelf();
    mediaLimits.validateSelf();
    safety.validate(
      FfmpegJob(
        id: 'editor-target-preflight',
        arguments: const ['-f', 'mp4', 'policy-output.mp4'],
        outputs: const [FfmpegOutput('policy-output.mp4', maxBytes: 1)],
      ),
    );
    if (maxInputBytes + maxOutputBytes > safety.maxWorkspaceBytes) {
      throw ArgumentError(
        'Editor render target limits do not fit the engine workspace.',
      );
    }
  }
}

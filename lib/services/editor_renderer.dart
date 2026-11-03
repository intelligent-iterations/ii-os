import 'dart:async';
import 'dart:typed_data';

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

enum EditorRenderStage { preparingLocalMedia, renderingMedia }

Future<void> disposeEditorEngineAfterActiveRender({
  required UniversalFfmpeg engine,
  EditorRenderCancellationToken? cancellation,
  Future<void>? activeRender,
}) async {
  cancellation?.cancel();
  if (activeRender != null) {
    try {
      await activeRender;
    } on Object {
      // Rendering failures are handled by the render owner. This wait exists
      // only to serialize token-driven engine cancellation before disposal.
    }
  }
  await engine.dispose();
}

final class EditorRenderResult {
  const EditorRenderResult({required this.plan, required this.engineResult});

  final EditorRenderPlan plan;
  final FfmpegResult engineResult;

  bool get isSuccess => engineResult.isSuccess;
  String get mediaType => plan.mediaType;
  Uint8List? get outputBytes => engineResult.outputBytes[plan.outputName];
}

/// Executes a compiled editor plan in the consuming app.
///
/// The editor package deliberately owns only validation and compilation. The
/// app owns engine lifecycle, cancellation, progress, and output handling.
final class EditorRenderer {
  const EditorRenderer({required this.engine, required this.compiler});

  final UniversalFfmpeg engine;
  final EditorCompositionCompiler compiler;

  Future<EditorRenderResult> render(
    EditorProject project, {
    EditorRenderCancellationToken? cancellation,
    void Function(EditorRenderStage stage)? onStage,
    FfmpegProgressCallback? onProgress,
  }) async {
    cancellation?.throwIfCancelled();
    onStage?.call(EditorRenderStage.preparingLocalMedia);
    final plan = await compiler.compile(project, cancellation: cancellation);
    cancellation?.throwIfCancelled();
    onStage?.call(EditorRenderStage.renderingMedia);

    var executionActive = true;
    var cancellationAdmitted = false;
    Object? cancellationError;
    StackTrace? cancellationStack;
    final cancellationOperation = cancellation?.whenCancelled.then<void>((
      _,
    ) async {
      if (!executionActive) return;
      cancellationAdmitted = true;
      try {
        await engine.cancel();
      } catch (error, stackTrace) {
        cancellationError = error;
        cancellationStack = stackTrace;
      }
    });
    if (cancellationOperation != null) unawaited(cancellationOperation);

    FfmpegResult? result;
    Object? executionError;
    StackTrace? executionStack;
    try {
      cancellation?.throwIfCancelled();
      result = await engine.execute(plan.job, onProgress: onProgress);
    } on Object catch (error, stackTrace) {
      executionError = error;
      executionStack = stackTrace;
    } finally {
      executionActive = false;
      if (cancellationAdmitted) await cancellationOperation!;
    }
    if ((cancellation?.isCancelled ?? false) || (result?.cancelled ?? false)) {
      if (cancellationOperation != null) await cancellationOperation;
      if (cancellationError case final error?) {
        Error.throwWithStackTrace(error, cancellationStack!);
      }
      throw const EditorRenderCancelledException();
    }
    if (executionError case final error?) {
      Error.throwWithStackTrace(error, executionStack!);
    }
    return EditorRenderResult(plan: plan, engineResult: result!);
  }
}

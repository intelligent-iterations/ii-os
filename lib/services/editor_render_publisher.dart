import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import '../models/editor_render_manifest.dart';
import '../repositories/source_asset_repository.dart';

/// Raised when the compiled render cannot be described for another machine.
final class EditorRenderNotPortable implements Exception {
  const EditorRenderNotPortable(this.message);

  final String message;

  @override
  String toString() => 'EditorRenderNotPortable: $message';
}

/// Turns a compiled render into something a workspace machine can run.
///
/// Every file the render reads is put in the workspace bucket first -- media
/// the project already owns is reused, and anything the compiler generated,
/// such as a rasterized caption, is uploaded here.
final class EditorRenderPublisher {
  const EditorRenderPublisher({required this.sourceAssets});

  final SourceAssetRepository sourceAssets;

  Future<EditorRenderManifest> publish({
    required String workspaceId,
    required String expectedBucket,
    required EditorRenderPlan plan,
    Map<String, String> knownAssetIds = const {},
    bool ghostMode = false,
  }) async {
    final sources = _inputSources(plan);
    final inputs = <EditorRenderInput>[];
    for (var index = 0; index < plan.job.inputs.length; index++) {
      final input = plan.job.inputs[index];
      if (input is! FfmpegBytesInput) {
        throw const EditorRenderNotPortable(
          'This render reads a file from this device, so it cannot run '
          'anywhere else.',
        );
      }
      final source = sources[index];
      if (!input.name.endsWith('.${source.fileExtension}')) {
        throw const EditorRenderNotPortable(
          'This render could not be matched to the media it reads.',
        );
      }
      final known = knownAssetIds[source.id];
      final assetId =
          known ??
          await sourceAssets.upload(
            workspaceId: workspaceId,
            expectedBucket: expectedBucket,
            filename: input.name,
            bytes: input.bytes,
            contentType: _contentTypeFor(source.fileExtension),
            ghostMode: ghostMode,
          );
      inputs.add(
        EditorRenderInput(
          name: input.name,
          assetId: assetId,
          byteLength: input.bytes.length,
        ),
      );
    }
    return EditorRenderManifest(
      arguments: List<String>.unmodifiable(plan.job.arguments),
      inputs: inputs,
      outputName: plan.outputName,
      mediaType: plan.mediaType,
      expectedDuration: Duration(
        microseconds: plan.composition.duration.microseconds,
      ),
      maxOutputBytes: plan.job.outputs.single.maxBytes ?? 0,
    );
  }

  /// The distinct media behind each numbered FFmpeg input, in the order the
  /// compiler declared them.
  List<MediaSource> _inputSources(EditorRenderPlan plan) {
    final order = <MediaSource>[];
    final seen = <String>{};
    for (final layer in plan.layers) {
      if (seen.add(layer.source.id)) order.add(layer.source);
    }
    if (order.length != plan.job.inputs.length) {
      throw const EditorRenderNotPortable(
        'This render could not be matched to the media it reads.',
      );
    }
    return order;
  }

  String _contentTypeFor(String extension) => switch (extension) {
    'mp4' || 'm4v' => 'video/mp4',
    'webm' => 'video/webm',
    'm4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'flac' => 'audio/flac',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    _ => throw EditorRenderNotPortable(
      'This render reads a .$extension file, which the workspace does not '
      'store.',
    ),
  };
}

import 'dart:convert';

import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import '../models/video_project.dart';
import '../repositories/editor_render_repository.dart';
import '../repositories/source_asset_repository.dart';
import 'editor_render_publisher.dart';
import 'video_editor_ffmpeg.dart';

/// How large a render may be before the catalogue refuses to carry it.
const editorRenderManifestLimit = 60000;

/// Hands a compiled export to a workspace machine.
abstract interface class EditorRenderDispatcher {
  /// Returns the id of the job now doing the work.
  Future<String> dispatch({
    required String workspaceId,
    required String expectedBucket,
    required EditorProject timeline,
    Map<String, VideoProjectMediaOrigin> origins = const {},
    bool ghostMode = false,
  });
}

/// Raised when a render is too large for the workspace to carry.
final class EditorRenderTooLarge implements Exception {
  const EditorRenderTooLarge();
}

final class WorkspaceEditorRenderDispatcher implements EditorRenderDispatcher {
  WorkspaceEditorRenderDispatcher({
    required this.renders,
    required this.sourceAssets,
    EditorCompositionCompiler? compiler,
  }) : compiler = compiler ?? videoEditorCompiler;

  final EditorRenderRepository renders;
  final SourceAssetRepository sourceAssets;
  final EditorCompositionCompiler compiler;

  @override
  Future<String> dispatch({
    required String workspaceId,
    required String expectedBucket,
    required EditorProject timeline,
    Map<String, VideoProjectMediaOrigin> origins = const {},
    bool ghostMode = false,
  }) async {
    // Compiling here rather than on the runner is the whole point: one
    // compiler means the workspace and the browser make the same video.
    final plan = await compiler.compile(timeline);
    final manifest = await EditorRenderPublisher(sourceAssets: sourceAssets)
        .publish(
          workspaceId: workspaceId,
          expectedBucket: expectedBucket,
          plan: plan,
          knownAssetIds: {
            for (final entry in origins.entries)
              if (entry.value case final WorkspaceSourceAssetOrigin origin)
                entry.key: origin.assetId,
          },
          ghostMode: ghostMode,
        );
    final encoded = jsonEncode(manifest.toJson());
    if (encoded.length > editorRenderManifestLimit) {
      throw const EditorRenderTooLarge();
    }
    return renders.submit(
      workspaceId: workspaceId,
      renderManifest: encoded,
      ghostMode: ghostMode,
    );
  }
}

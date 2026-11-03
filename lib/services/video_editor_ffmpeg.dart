import 'package:flutter/foundation.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'video_editor_ffmpeg_workspace.dart';
import 'video_editor_render_readiness.dart';

const _webFfmpegScriptSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_FFMPEG_JS_SHA256',
);
const _webCoreScriptSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_JS_SHA256',
);
const _webCoreWasmSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_WASM_SHA256',
);
const _desktopFfmpegPath = String.fromEnvironment('II_FFMPEG_PATH');
const _desktopFfmpegSha256 = String.fromEnvironment('II_FFMPEG_SHA256');
const _desktopFfprobePath = String.fromEnvironment('II_FFPROBE_PATH');
const _desktopFfprobeSha256 = String.fromEnvironment('II_FFPROBE_SHA256');

/// Builds the one target used for render feasibility and both render paths.
///
/// Keeping this pure makes both platform profiles testable on one host.
EditorRenderTarget videoEditorRenderTargetFor({required bool browser}) =>
    browser
    ? const EditorRenderTarget(
        editorLimits: EditorLimits(
          maxDuration: Duration(minutes: 2),
          maxCaptionRasterBytes: 8 * 1024 * 1024,
          maxCaptionPixels: 4 * 1024 * 1024,
          maxCaptionTotalRasterBytes: 16 * 1024 * 1024,
          maxCaptionTotalPixels: 16 * 1024 * 1024,
        ),
        mediaLimits: MediaLimits(
          maxInputBytes: 128 * 1024 * 1024,
          maxDeclaredMediaBytes: 112 * 1024 * 1024,
          maxSourceBytes: 112 * 1024 * 1024,
          maxOutputBytes: 64 * 1024 * 1024,
          maxEstimatedOutputBytes: 64 * 1024 * 1024 * 92 ~/ 100,
          sourceReadTimeout: Duration(minutes: 2),
        ),
        safety: FfmpegSafetyPolicy(
          maxInputBytes: 112 * 1024 * 1024,
          maxTotalInputBytes: 128 * 1024 * 1024,
          maxOutputBytes: 64 * 1024 * 1024,
          maxTotalOutputBytes: 64 * 1024 * 1024,
          maxWorkspaceBytes: 192 * 1024 * 1024,
          defaultTimeout: Duration(minutes: 15),
          maxTimeout: Duration(hours: 1),
        ),
      )
    : const EditorRenderTarget(
        editorLimits: EditorLimits(maxDuration: Duration(minutes: 20)),
        mediaLimits: MediaLimits(
          maxInputBytes: 320 * 1024 * 1024,
          maxDeclaredMediaBytes: 256 * 1024 * 1024,
          maxSourceBytes: 128 * 1024 * 1024,
          maxOutputBytes: 512 * 1024 * 1024,
          maxEstimatedOutputBytes: 512 * 1024 * 1024 * 92 ~/ 100,
          sourceReadTimeout: Duration(minutes: 2),
        ),
        safety: FfmpegSafetyPolicy(
          maxInputBytes: 128 * 1024 * 1024,
          maxTotalInputBytes: 320 * 1024 * 1024,
          maxOutputBytes: 512 * 1024 * 1024,
          maxTotalOutputBytes: 512 * 1024 * 1024,
          maxWorkspaceBytes: 1024 * 1024 * 1024,
          defaultTimeout: Duration(minutes: 15),
          maxTimeout: Duration(hours: 1),
        ),
      );

final EditorRenderTarget videoEditorRenderTarget = videoEditorRenderTargetFor(
  browser: kIsWeb,
);
final MediaLimits videoEditorMediaLimits = videoEditorRenderTarget.mediaLimits;
final FfmpegSafetyPolicy videoEditorSafety = videoEditorRenderTarget.safety;
final EditorCompositionCompiler videoEditorCompiler =
    EditorCompositionCompiler.forTarget(videoEditorRenderTarget);

final VideoEditorRenderReadinessService videoEditorRenderReadiness =
    VideoEditorRenderReadinessService(compiler: videoEditorCompiler);

UniversalFfmpeg createVideoEditorFfmpeg() =>
    UniversalFfmpeg(configuration: videoEditorFfmpegConfiguration());

FfmpegConfiguration videoEditorFfmpegConfiguration() {
  if (kIsWeb) {
    if (!_isSha256(_webFfmpegScriptSha256) ||
        !_isSha256(_webCoreScriptSha256) ||
        !_isSha256(_webCoreWasmSha256)) {
      throw StateError(
        'The ii-os browser build is missing its attested FFmpeg WebAssembly '
        'artifact digests.',
      );
    }
    return FfmpegConfiguration(
      safety: videoEditorSafety,
      webBundle: const FfmpegWebBundle(
        ffmpegScriptUrl: 'ffmpeg/ffmpeg.js',
        ffmpegScriptSha256: _webFfmpegScriptSha256,
        coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
        coreScriptSha256: _webCoreScriptSha256,
        coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
        coreWasmSha256: _webCoreWasmSha256,
      ),
    );
  }

  final nativeWorkspaceRoot = videoEditorNativeWorkspaceRoot();
  final desktop = videoEditorUsesDesktopBundle(
    platform: defaultTargetPlatform,
    nativeWorkspaceRoot: nativeWorkspaceRoot,
  );
  final desktopConfigured =
      _desktopFfmpegPath.isNotEmpty &&
      _isSha256(_desktopFfmpegSha256) &&
      _desktopFfprobePath.isNotEmpty &&
      _isSha256(_desktopFfprobeSha256);
  return FfmpegConfiguration(
    safety: videoEditorSafety,
    nativeWorkspaceRoot: nativeWorkspaceRoot,
    desktopBundle: desktop && desktopConfigured
        ? const FfmpegDesktopBundle(
            ffmpegPath: _desktopFfmpegPath,
            ffmpegSha256: _desktopFfmpegSha256,
            ffprobePath: _desktopFfprobePath,
            ffprobeSha256: _desktopFfprobeSha256,
          )
        : null,
  );
}

/// Whether [platform] should be handed the bundled desktop FFmpeg binaries.
///
/// Windows is named explicitly rather than inferred. [nativeWorkspaceRoot] is
/// non-null only on Linux and macOS -- those are the platforms that get an owned
/// temp workspace -- so deriving desktop from it alone would silently drop
/// Windows, which does run the desktop bundle and just does not take that
/// workspace.
///
/// Pure and separate from [videoEditorFfmpegConfiguration] so every target
/// platform is testable from one host. The configuration itself reads
/// `defaultTargetPlatform`, so a host-based test can only ever prove the one
/// platform it happens to run on.
bool videoEditorUsesDesktopBundle({
  required TargetPlatform platform,
  required String? nativeWorkspaceRoot,
}) => nativeWorkspaceRoot != null || platform == TargetPlatform.windows;

bool _isSha256(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

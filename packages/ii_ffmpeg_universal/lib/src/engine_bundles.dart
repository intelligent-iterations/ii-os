part of 'configuration.dart';

/// Exact desktop executables selected and attested by the consuming app.
///
/// Desktop applications must package reviewed FFmpeg binaries and configure
/// their absolute paths and SHA-256 digests. The backend never searches PATH.
final class FfmpegDesktopBundle {
  const FfmpegDesktopBundle({
    required this.ffmpegPath,
    required this.ffmpegSha256,
    required this.ffprobePath,
    required this.ffprobeSha256,
    this.dynamicLibraries = const [],
  });

  final String ffmpegPath;
  final String ffmpegSha256;
  final String ffprobePath;
  final String ffprobeSha256;
  final List<FfmpegDesktopDependency> dynamicLibraries;
}

final class FfmpegDesktopDependency {
  const FfmpegDesktopDependency({
    required this.name,
    required this.path,
    required this.sha256,
  });

  final String name;
  final String path;
  final String sha256;
}

/// Exact same-origin ffmpeg.wasm assets selected by the consuming web app.
///
/// Browser codec and license choices belong to the application. The package
/// verifies every byte before evaluation, then checks that the selected core
/// exposes the reviewed heap and FFprobe hooks and passes the real MEMFS quota
/// self-test.
final class FfmpegWebBundle {
  const FfmpegWebBundle({
    required this.ffmpegScriptUrl,
    required this.ffmpegScriptSha256,
    required this.coreScriptUrl,
    required this.coreScriptSha256,
    required this.coreWasmUrl,
    required this.coreWasmSha256,
  });

  final String ffmpegScriptUrl;
  final String ffmpegScriptSha256;
  final String coreScriptUrl;
  final String coreScriptSha256;
  final String coreWasmUrl;
  final String coreWasmSha256;
}

final class FfmpegConfiguration {
  const FfmpegConfiguration({
    this.safety = const FfmpegSafetyPolicy(),
    this.desktopBundle,
    this.webBundle,
    this.nativeWorkspaceRoot,
  });

  final FfmpegSafetyPolicy safety;
  final FfmpegDesktopBundle? desktopBundle;
  final FfmpegWebBundle? webBundle;

  /// Dedicated application-private directory used only for owned native
  /// processing workspaces. It must be absolute and either absent or already
  /// carry this package's root ownership marker. Mobile app sandboxes may omit
  /// it; desktop release configurations must provide it explicitly.
  final String? nativeWorkspaceRoot;
}

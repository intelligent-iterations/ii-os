part of 'io_backend.dart';

final class _StagedDesktopBundle {
  const _StagedDesktopBundle(this.ffmpeg, this.ffprobe, this.directory);

  final String ffmpeg;
  final String ffprobe;
  final String directory;
}

typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);

extension on IoFfmpegBackend {
  Future<void> _prepareDesktopBundle() async {
    if (_stagedDesktopBundle != null) return;
    final workspace = await IoWorkspace.create(
      'desktop_engine_bundle',
      root: _workspaceRoot,
    );
    final bundle = _desktopBundle!;
    final engineDirectory = Directory(
      p.join(workspace.directory.path, '.ii-engine'),
    );
    await engineDirectory.create();
    try {
      final ffmpegName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final ffprobeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
      final ffmpeg = await _stageVerifiedDesktopFile(
        bundle.ffmpegPath,
        bundle.ffmpegSha256,
        engineDirectory,
        ffmpegName,
      );
      final ffprobe = await _stageVerifiedDesktopFile(
        bundle.ffprobePath,
        bundle.ffprobeSha256,
        engineDirectory,
        ffprobeName,
      );
      final names = <String>{
        ffmpegName.toLowerCase(),
        ffprobeName.toLowerCase(),
      };
      final libraries = <String>[];
      for (final dependency in bundle.dynamicLibraries) {
        final name = dependency.name;
        if (name.isEmpty ||
            name != p.basename(name) ||
            !names.add(name.toLowerCase())) {
          throw const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'Desktop engine dependency names must be unique base names.',
          );
        }
        libraries.add(
          await _stageVerifiedDesktopFile(
            dependency.path,
            dependency.sha256,
            engineDirectory,
            name,
          ),
        );
      }
      await _sealDesktopFiles([ffmpeg, ffprobe], libraries);
      _desktopEngineWorkspace = workspace;
      _stagedDesktopBundle = _StagedDesktopBundle(
        ffmpeg,
        ffprobe,
        engineDirectory.path,
      );
    } catch (_) {
      await workspace.dispose();
      rethrow;
    }
  }

  Future<_StagedDesktopBundle> _desktopBundleReady() async {
    await _prepareDesktopBundle();
    return _stagedDesktopBundle!;
  }

  Future<void> _disposeDesktopBundle() async {
    final workspace = _desktopEngineWorkspace;
    _desktopEngineWorkspace = null;
    _stagedDesktopBundle = null;
    if (workspace != null) await workspace.dispose();
  }

  Future<String> _stageVerifiedDesktopFile(
    String source,
    String expectedSha256,
    Directory destination,
    String name,
  ) async {
    final digest = expectedSha256.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) || !p.isAbsolute(source)) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'Desktop engine files need absolute paths and exact SHA-256 values.',
      );
    }
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'A desktop engine file is missing, non-regular, or a symbolic link.',
      );
    }
    final output = File(p.join(destination.path, name));
    if (await output.exists()) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'A staged desktop engine file name was reused.',
      );
    }
    final sink = output.openWrite(mode: FileMode.writeOnly);
    try {
      await sink.addStream(File(source).openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    final actual = await sha256.bind(output.openRead()).first;
    if (actual.toString() != digest) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'A desktop engine file failed SHA-256 verification while staging.',
      );
    }
    return output.path;
  }

  Future<void> _sealDesktopFiles(
    List<String> executables,
    List<String> libraries,
  ) async {
    if (Platform.isWindows) return;
    final chmod = DynamicLibrary.process()
        .lookupFunction<_ChmodNative, _ChmodDart>('chmod');
    for (final file in [...executables, ...libraries]) {
      final pointer = file.toNativeUtf8();
      try {
        final mode = executables.contains(file) ? 0x140 : 0x100;
        if (chmod(pointer, mode) != 0) {
          throw const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'A staged desktop engine file could not be sealed.',
          );
        }
      } finally {
        malloc.free(pointer);
      }
    }
  }
}

part of 'live_process_e2e_test.dart';

late String _liveWorkspaceRoot;

String _resultDiagnostics(FfmpegResult result) =>
    'exit=${result.exitCode} cancelled=${result.cancelled} '
    'timedOut=${result.timedOut}\n${result.logs.join('\n')}';

Future<FfmpegDesktopBundle> _resolveTestDesktopBundle() async {
  final explicitRoot = Platform.environment['II_FFMPEG_LIVE_TEST_ENGINE_ROOT'];
  final explicitManifest =
      Platform.environment['II_FFMPEG_LIVE_TEST_MANIFEST_SHA256'];
  if (explicitRoot != null || explicitManifest != null) {
    if (explicitRoot == null || explicitManifest == null) {
      throw StateError(
        'The explicit live desktop engine identity is incomplete.',
      );
    }
    return loadAttestedFfmpegDesktopBundle(
      rootPath: explicitRoot,
      manifestSha256: explicitManifest,
    );
  }
  if (Platform.environment['II_FFMPEG_ALLOW_AMBIENT_TEST_ENGINE'] != 'true') {
    throw StateError(
      'Live desktop tests require an explicit attested engine. Set '
      'II_FFMPEG_ALLOW_AMBIENT_TEST_ENGINE=true only for a deliberate '
      'developer test against the local PATH engine.',
    );
  }
  final ffmpegPath = await _resolveTestExecutable('ffmpeg');
  final ffprobePath = await _resolveTestExecutable('ffprobe');
  return FfmpegDesktopBundle(
    ffmpegPath: ffmpegPath,
    ffmpegSha256: await _sha256File(ffmpegPath),
    ffprobePath: ffprobePath,
    ffprobeSha256: await _sha256File(ffprobePath),
    dynamicLibraries: await _desktopDependencies([ffmpegPath, ffprobePath]),
  );
}

FfmpegJob _slowNullJob(String id) => FfmpegJob(
  id: id,
  arguments: const [
    '-re',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=s=160x90:r=25:d=5',
    '-f',
    'null',
    '-',
  ],
);

Future<Directory> _ownedTestDirectory(String purpose) async {
  final directory = await Directory.systemTemp.createTemp(
    'ii_ffmpeg_universal_${purpose}_',
  );
  final marker = File('${directory.path}/.ii-disposable-owner');
  final markerValue = 'ii-ffmpeg-universal-test-${directory.path}';
  await marker.writeAsString(markerValue);
  addTearDown(() async {
    if (await marker.exists() && await marker.readAsString() == markerValue) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

Set<String> _workspaces(String jobId) {
  final root = Directory(_liveWorkspaceRoot);
  if (!root.existsSync()) return const {};
  return root
      .listSync(followLinks: false)
      .whereType<Directory>()
      .map((directory) => directory.path)
      .where((value) => value.contains('ii_ffmpeg_universal_${jobId}_'))
      .toSet();
}

Future<File> _waitForIsolatedPathInput({
  required String jobId,
  required String inputName,
  required int expectedLength,
  required String expectedSha256,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    for (final workspace in _workspaces(jobId)) {
      final candidate = File(p.join(workspace, inputName));
      if (await FileSystemEntity.type(candidate.path, followLinks: false) ==
          FileSystemEntityType.file) {
        try {
          if (await candidate.length() == expectedLength &&
              await _sha256File(candidate.path) == expectedSha256) {
            return candidate;
          }
        } on FileSystemException {
          // The owned workspace may disappear between discovery and hashing.
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError(
    'Timed out waiting for the isolated $inputName copy for $jobId.',
  );
}

Future<String> _resolveTestExecutable(String name) async {
  final resolver = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(resolver, [name]);
  if (result.exitCode != 0) {
    throw StateError('$name is required for the live process test.');
  }
  final candidate = LineSplitter.split(
    '${result.stdout}',
  ).map((line) => line.trim()).firstWhere((line) => line.isNotEmpty);
  return File(candidate).resolveSymbolicLinks();
}

Future<String> _sha256File(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<List<FfmpegDesktopDependency>> _desktopDependencies(
  List<String> executables,
) async {
  if (Platform.isWindows) return const [];
  final queue = [...executables];
  final visited = <String>{};
  final dependencies = <String, String>{};
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!visited.add(current)) continue;
    final discovered = Platform.isMacOS
        ? await _machODependencies(current)
        : await _elfDependencies(current);
    for (final candidate in discovered.entries) {
      final resolved = await File(candidate.value).resolveSymbolicLinks();
      final previous = dependencies[candidate.key];
      if (previous != null && previous != resolved) {
        throw StateError('dependency name collision: ${candidate.key}');
      }
      if (previous == null) {
        dependencies[candidate.key] = resolved;
        queue.add(resolved);
      }
    }
  }
  final result = <FfmpegDesktopDependency>[];
  for (final entry
      in dependencies.entries.toList()
        ..sort((first, second) => first.key.compareTo(second.key))) {
    result.add(
      FfmpegDesktopDependency(
        name: entry.key,
        path: entry.value,
        sha256: await _sha256File(entry.value),
      ),
    );
  }
  return result;
}

Future<Map<String, String>> _machODependencies(String file) async {
  final result = await Process.run('/usr/bin/otool', ['-L', file]);
  if (result.exitCode != 0) throw StateError('otool failed for $file');
  final dependencies = <String, String>{};
  for (final line in LineSplitter.split('${result.stdout}').skip(1)) {
    final runtimePath = line.trim().split(' (').first;
    if (runtimePath.startsWith('/') &&
        !runtimePath.startsWith('/usr/lib/') &&
        !runtimePath.startsWith('/System/Library/')) {
      dependencies[p.basename(runtimePath)] = runtimePath;
    } else if (runtimePath.startsWith('@loader_path/')) {
      final resolved = p.normalize(
        p.join(p.dirname(file), runtimePath.substring('@loader_path/'.length)),
      );
      if (p.dirname(file) != p.dirname(resolved)) {
        throw StateError('Mach-O dependency escapes its loader directory.');
      }
      dependencies[p.basename(runtimePath)] = resolved;
    }
  }
  return dependencies;
}

Future<Map<String, String>> _elfDependencies(String file) async {
  final result = await Process.run('/usr/bin/ldd', [file]);
  if (result.exitCode != 0) throw StateError('ldd failed for $file');
  final systemNames = {
    'libc.so.6',
    'libdl.so.2',
    'libgcc_s.so.1',
    'libm.so.6',
    'libpthread.so.0',
    'libresolv.so.2',
    'librt.so.1',
    'libstdc++.so.6',
  };
  final paths = <String, String>{};
  for (final line in LineSplitter.split('${result.stdout}')) {
    final value = line.trim();
    final rawName = value.split(RegExp(r'\s+')).first;
    final name = p.basename(rawName);
    if (systemNames.contains(name)) continue;
    final match = RegExp(r'(?:=>\s+)?(/[^ ]+)\s+\(').firstMatch(value);
    final path = match?.group(1);
    if (path != null) paths[name] = path;
  }
  return paths;
}

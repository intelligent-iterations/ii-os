// Resolves the real FFmpeg on this machine so a test can render through it.
//
// This is the counterpart of the same helper in ii-flutter-video-editor. It
// is duplicated rather than shared because that package does not publish its
// test harness, and a render proof that mocks the encoder proves nothing
// about the encoder.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';

Future<FfmpegDesktopBundle> resolveDesktopBundle() async {
  final root = Platform.environment['II_FFMPEG_LIVE_TEST_ENGINE_ROOT']?.trim();
  final manifest = Platform.environment['II_FFMPEG_LIVE_TEST_MANIFEST_SHA256']
      ?.trim();
  if ((root?.isNotEmpty ?? false) || (manifest?.isNotEmpty ?? false)) {
    if (root == null || root.isEmpty || manifest == null || manifest.isEmpty) {
      throw StateError(
        'Both explicit desktop engine identity variables are required.',
      );
    }
    return loadAttestedFfmpegDesktopBundle(
      rootPath: root,
      manifestSha256: manifest,
    );
  }
  final ffmpeg = await _resolveExecutable('ffmpeg');
  final ffprobe = await _resolveExecutable('ffprobe');
  return _desktopBundle(ffmpeg, ffprobe);
}

Future<({String path, String sha256})> _resolveExecutable(String name) async {
  final pathValue = Platform.environment['PATH'];
  if (pathValue == null) throw StateError('PATH is not configured.');
  for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    final candidate = File.fromUri(
      Directory(directory).uri.resolve(Platform.isWindows ? '$name.exe' : name),
    );
    if (!await candidate.exists()) continue;
    final resolved = await candidate.resolveSymbolicLinks();
    if (await FileSystemEntity.type(resolved, followLinks: false) !=
        FileSystemEntityType.file) {
      continue;
    }
    return (path: resolved, sha256: await _sha256File(resolved));
  }
  throw StateError('Unable to resolve $name from PATH.');
}

Future<FfmpegDesktopBundle> _desktopBundle(
  ({String path, String sha256}) ffmpeg,
  ({String path, String sha256}) ffprobe,
) async => FfmpegDesktopBundle(
  ffmpegPath: ffmpeg.path,
  ffmpegSha256: ffmpeg.sha256,
  ffprobePath: ffprobe.path,
  ffprobeSha256: ffprobe.sha256,
  dynamicLibraries: await _desktopDependencies([ffmpeg.path, ffprobe.path]),
);

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
    for (final entry in discovered.entries) {
      final resolved = await File(entry.value).resolveSymbolicLinks();
      final previous = dependencies[entry.key];
      if (previous != null && previous != resolved) {
        throw StateError('Dependency name collision: ${entry.key}.');
      }
      if (previous == null) {
        dependencies[entry.key] = resolved;
        queue.add(resolved);
      }
    }
  }
  final result = <FfmpegDesktopDependency>[];
  for (final entry
      in dependencies.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
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
  if (result.exitCode != 0) throw StateError('otool failed for $file.');
  final dependencies = <String, String>{};
  for (final line in LineSplitter.split('${result.stdout}').skip(1)) {
    final runtimePath = line.trim().split(' (').first;
    if (runtimePath.startsWith('/') &&
        !runtimePath.startsWith('/usr/lib/') &&
        !runtimePath.startsWith('/System/Library/')) {
      dependencies[_basename(runtimePath)] = runtimePath;
    } else if (runtimePath.startsWith('@loader_path/')) {
      final resolved = File(file).parent.uri
          .resolve(runtimePath.substring('@loader_path/'.length))
          .toFilePath();
      if (File(resolved).parent.path != File(file).parent.path) {
        throw StateError('Mach-O dependency escapes its loader directory.');
      }
      dependencies[_basename(runtimePath)] = resolved;
    }
  }
  return dependencies;
}

Future<Map<String, String>> _elfDependencies(String file) async {
  final result = await Process.run('/usr/bin/ldd', [file]);
  if (result.exitCode != 0) throw StateError('ldd failed for $file.');
  const systemNames = {
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
    final name = value.split(RegExp(r'\s+')).first;
    if (systemNames.contains(name)) continue;
    final match = RegExp(r'(?:=>\s+)?(/[^ ]+)\s+\(').firstMatch(value);
    final path = match?.group(1);
    if (path != null) {
      // Direct-loader entries from ldd begin with an absolute path rather
      // than a soname. The desktop bundle contract accepts base names only,
      // both to keep staging inside the owned engine directory and to make
      // collisions explicit.
      paths[_basename(name)] = path;
    }
  }
  return paths;
}

String _basename(String path) => path.replaceAll(r'\', '/').split('/').last;

Future<String> _sha256File(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

final class OwnedState {
  OwnedState(this.directory, this.owner);

  final Directory directory;
  final String owner;

  static Future<OwnedState> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'ii-video-editor-disposable-',
    );
    final owner =
        'ii-video-editor-e2e-$pid-${DateTime.now().microsecondsSinceEpoch}';
    await File.fromUri(
      directory.uri.resolve('.ii-disposable-owner'),
    ).writeAsString(owner, flush: true);
    return OwnedState(directory, owner);
  }

  Future<void> dispose() async {
    final marker = File.fromUri(directory.uri.resolve('.ii-disposable-owner'));
    if (!await marker.exists() || await marker.readAsString() != owner) {
      throw StateError(
        'Refusing to remove test state without exact ownership.',
      );
    }
    await directory.delete(recursive: true);
  }
}

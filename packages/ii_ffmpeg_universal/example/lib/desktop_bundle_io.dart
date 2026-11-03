import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:path/path.dart' as p;

const _manifestSha256 = String.fromEnvironment(
  'II_FFMPEG_DESKTOP_MANIFEST_SHA256',
);

final String _integrationWorkspaceRoot = p.join(
  Directory.systemTemp.path,
  'ii_ffmpeg_universal_example_${pid}_'
  '${List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}',
);

String exampleNativeWorkspaceRoot() => p.join(
  Directory.systemTemp.path,
  'ii_ffmpeg_universal_example_workspaces_v1',
);

String exampleIntegrationNativeWorkspaceRoot() => _integrationWorkspaceRoot;

Future<void> cleanupExampleIntegrationNativeWorkspaceRoot(
  String? rootPath,
) async {
  if (rootPath == null ||
      !p.isAbsolute(rootPath) ||
      rootPath != _integrationWorkspaceRoot) {
    throw StateError(
      'Refusing to clean an unrecognized native workspace root.',
    );
  }
  final rootType = await FileSystemEntity.type(rootPath, followLinks: false);
  if (rootType == FileSystemEntityType.notFound) return;
  if (rootType != FileSystemEntityType.directory) {
    throw StateError('The native workspace root is not a regular directory.');
  }
  final root = Directory(rootPath);
  final marker = File(p.join(rootPath, '.ii-workspace-root-owner'));
  final lockFile = File(p.join(rootPath, '.ii-root-lock'));
  if (await FileSystemEntity.type(marker.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await FileSystemEntity.type(lockFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw StateError('Native workspace ownership files are missing or linked.');
  }
  final bytes = await marker
      .openRead(0, 4097)
      .fold<List<int>>(<int>[], (value, chunk) => value..addAll(chunk));
  final record = bytes.length <= 4096 ? jsonDecode(utf8.decode(bytes)) : null;
  if (record is! Map<String, Object?> ||
      record['schema'] != 1 ||
      record['owner'] != 'ii-ffmpeg-universal' ||
      record['token'] is! String ||
      !RegExp(r'^[0-9a-f]{48}$').hasMatch(record['token']! as String)) {
    throw StateError('Native workspace root ownership is invalid.');
  }
  final entries = await root.list(followLinks: false).toList();
  final names = entries.map((value) => p.basename(value.path)).toSet();
  if (entries.length != 2 ||
      !names.contains('.ii-workspace-root-owner') ||
      !names.contains('.ii-root-lock')) {
    throw StateError('Native workspace cleanup left owned session state.');
  }
  final lock = await lockFile.open(mode: FileMode.write);
  try {
    await lock.lock(FileLock.exclusive);
    await lock.unlock();
  } finally {
    await lock.close();
  }
  await root.delete(recursive: true);
  if (await root.exists()) {
    throw StateError('Native workspace root cleanup was not confirmed.');
  }
}

Future<FfmpegDesktopBundle?> loadExampleDesktopBundle() async {
  if (!Platform.isLinux && !Platform.isMacOS) return null;
  final executableDirectory = p.dirname(Platform.resolvedExecutable);
  final root = Platform.isMacOS
      ? p.normalize(
          p.join(
            executableDirectory,
            '..',
            'Frameworks',
            'App.framework',
            'Resources',
            'flutter_assets',
            'assets',
            'desktop_engine',
          ),
        )
      : p.join(
          executableDirectory,
          'data',
          'flutter_assets',
          'assets',
          'desktop_engine',
        );
  return loadAttestedFfmpegDesktopBundle(
    rootPath: root,
    manifestSha256: _manifestSha256,
  );
}

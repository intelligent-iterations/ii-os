part of 'io_workspace.dart';

const String _rootMarkerName = '.ii-workspace-root-owner';
const String _rootLockName = '.ii-root-lock';
const int _rootSchema = 1;
const int _maxMarkerBytes = 4096;
const int _maxRecoveryEntries = 256;
const int _maxRecoverableWorkspaceBytes = 2 * 1024 * 1024 * 1024;
const Duration _defaultRecoveryAge = Duration(hours: 24);

final class _OwnedWorkspaceRoot {
  const _OwnedWorkspaceRoot(
    this.directory,
    this.token, {
    required this.recovered,
  });

  final Directory directory;
  final String token;
  final int recovered;
}

Directory _defaultWorkspaceRoot() => Directory(
  path.join(Directory.systemTemp.path, 'ii_ffmpeg_universal_workspaces_v1'),
);

Future<_OwnedWorkspaceRoot> _prepareWorkspaceRoot(
  Directory root, {
  Duration minimumAge = _defaultRecoveryAge,
  DateTime? now,
}) async {
  if (minimumAge < Duration.zero || !root.isAbsolute) {
    throw const FfmpegException(
      FfmpegErrorCode.executionFailed,
      'The native workspace root or recovery age is invalid.',
    );
  }
  final type = await FileSystemEntity.type(root.path, followLinks: false);
  var created = false;
  if (type == FileSystemEntityType.notFound) {
    try {
      await root.create();
      created = true;
    } on FileSystemException {
      if (!await root.exists()) rethrow;
    }
  } else if (type != FileSystemEntityType.directory) {
    throw const FfmpegException(
      FfmpegErrorCode.executionFailed,
      'The native workspace root is not an owned regular directory.',
    );
  }

  final rootLock = await File(
    path.join(root.path, _rootLockName),
  ).open(mode: FileMode.write);
  await rootLock.lock(FileLock.blockingExclusive);
  try {
    final marker = File(path.join(root.path, _rootMarkerName));
    Map<String, Object?> record;
    if (!await marker.exists()) {
      if (!created) {
        throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'Refusing an existing unowned native workspace root.',
        );
      }
      final token = IoWorkspace._randomToken();
      record = {
        'schema': _rootSchema,
        'owner': IoWorkspace._owner,
        'token': token,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      await marker.writeAsString(jsonEncode(record), flush: true);
      _makeWorkspaceRootPrivate(root.path);
    } else {
      try {
        record = await IoWorkspace._readMarker(marker);
      } on Object {
        throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'The native workspace root marker is malformed.',
        );
      }
    }
    final token = record['token'];
    if (record['schema'] != _rootSchema ||
        record['owner'] != IoWorkspace._owner ||
        token is! String ||
        !_tokenPattern.hasMatch(token)) {
      throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The native workspace root ownership could not be proven.',
      );
    }
    final recovered = await _recoverOwnedWorkspaces(
      root,
      token,
      minimumAge,
      (now ?? DateTime.now()).toUtc(),
    );
    return _OwnedWorkspaceRoot(root, token, recovered: recovered);
  } finally {
    await rootLock.unlock();
    await rootLock.close();
  }
}

final RegExp _tokenPattern = RegExp(r'^[0-9a-f]{48}$');

Future<int> _recoverOwnedWorkspaces(
  Directory root,
  String rootToken,
  Duration minimumAge,
  DateTime now,
) async {
  final candidates = <Directory>[];
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory ||
        !path.basename(entity.path).startsWith('ii_ffmpeg_universal_')) {
      continue;
    }
    candidates.add(entity);
    if (candidates.length > _maxRecoveryEntries) {
      throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The owned workspace recovery entry limit was exceeded.',
      );
    }
  }

  var recovered = 0;
  for (final directory in candidates) {
    final marker = File(path.join(directory.path, IoWorkspace._markerName));
    final lockFile = File(path.join(directory.path, IoWorkspace._lockName));
    Map<String, Object?> record;
    try {
      record = await IoWorkspace._readMarker(marker);
    } on Object {
      continue;
    }
    if (!_validWorkspaceRecord(directory, record, rootToken, now, minimumAge)) {
      continue;
    }
    RandomAccessFile? activeLock;
    try {
      activeLock = await lockFile.open(mode: FileMode.write);
      await activeLock.lock(FileLock.exclusive);
    } on FileSystemException {
      await activeLock?.close();
      continue;
    }
    try {
      final confirmed = await IoWorkspace._readMarker(marker);
      if (!_sameWorkspaceRecord(record, confirmed) ||
          !_validWorkspaceRecord(
            directory,
            confirmed,
            rootToken,
            now,
            minimumAge,
          )) {
        continue;
      }
      if (!await _recoverPublicationJournals(directory, confirmed)) continue;
      final size = await _boundedWorkspaceSize(directory);
      if (size > _maxRecoverableWorkspaceBytes) continue;
      await directory.delete(recursive: true);
      recovered += 1;
    } on FileSystemException {
      // Preserve state if any identity or deletion operation races or fails.
    } finally {
      try {
        await activeLock.close();
      } on FileSystemException {
        // The directory and lock inode may already be gone after exact cleanup.
      }
    }
  }
  return recovered;
}

bool _validWorkspaceRecord(
  Directory directory,
  Map<String, Object?> record,
  String rootToken,
  DateTime now,
  Duration minimumAge,
) {
  final token = record['token'];
  final workspaceId = record['workspace_id'];
  final createdRaw = record['created_at'];
  final ownerPid = record['pid'];
  final created = createdRaw is String
      ? DateTime.tryParse(createdRaw)?.toUtc()
      : null;
  return record['owner'] == IoWorkspace._owner &&
      record['root_token'] == rootToken &&
      token is String &&
      _tokenPattern.hasMatch(token) &&
      workspaceId == path.basename(directory.path) &&
      ownerPid is int &&
      ownerPid > 0 &&
      ownerPid != pid &&
      created != null &&
      !created.isAfter(now) &&
      now.difference(created) >= minimumAge;
}

bool _sameWorkspaceRecord(
  Map<String, Object?> first,
  Map<String, Object?> second,
) =>
    first['owner'] == second['owner'] &&
    first['token'] == second['token'] &&
    first['root_token'] == second['root_token'] &&
    first['workspace_id'] == second['workspace_id'] &&
    first['created_at'] == second['created_at'] &&
    first['pid'] == second['pid'];

Future<int> _boundedWorkspaceSize(Directory directory) async {
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    total += await entity.length();
    if (total > _maxRecoverableWorkspaceBytes) return total;
  }
  return total;
}

typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);

void _makeWorkspaceRootPrivate(String rootPath) {
  if (Platform.isWindows) return;
  final chmod = DynamicLibrary.process()
      .lookupFunction<_ChmodNative, _ChmodDart>('chmod');
  final value = rootPath.toNativeUtf8();
  try {
    if (chmod(value, 0x1c0) != 0) {
      throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The native workspace root could not be made application-private.',
      );
    }
  } finally {
    malloc.free(value);
  }
}

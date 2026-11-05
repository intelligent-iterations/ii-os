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
  // A private leaf alone is insufficient inside an attacker-owned parent:
  // that parent could rename it after validation. Canonical ancestors must
  // be owned by this uid or the OS and not writable by other users (except
  // OS-owned sticky directories, whose rename rules protect our owned leaf).
  root = await _canonicalTrustedWorkspaceRoot(root);
  final created = _mkdirPrivateWorkspaceRoot(root.path);
  _requireWorkspaceDirectory(root.path, private: true);
  final marker = File(path.join(root.path, _rootMarkerName));
  if (created) {
    // Publish the marker before yielding, so concurrent instances in this
    // isolate cannot observe a half-initialized newly owned root.
    marker.createSync(exclusive: true);
    marker.writeAsStringSync(
      jsonEncode({
        'schema': _rootSchema,
        'owner': IoWorkspace._owner,
        'token': IoWorkspace._randomToken(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }
  _requireOwnedWorkspaceFile(marker.path);
  final rootLock = await _openWorkspaceLock(
    path.join(root.path, _rootLockName),
    create: true,
  );
  await rootLock.lock(FileLock.blockingExclusive);
  try {
    Map<String, Object?> record;
    try {
      record = await IoWorkspace._readMarker(marker);
    } on Object {
      throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The native workspace root marker is malformed.',
      );
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
      activeLock = await _openWorkspaceLock(lockFile.path, create: false);
      await activeLock.lock(FileLock.exclusive);
    } on Object {
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

typedef _WorkspaceMkdirNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _WorkspaceMkdirDart = int Function(Pointer<Utf8>, int);
// open's mode is variadic. In particular, Apple Silicon passes variadic
// arguments differently from fixed arguments, so a fixed third parameter
// would create locks with unrelated stack bytes as their permissions.
typedef _WorkspaceOpenNative =
    Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Uint32,)>);
typedef _WorkspaceOpenDart = int Function(Pointer<Utf8>, int, int);
typedef _WorkspaceFstatNative = Int32 Function(Int32, Pointer<Uint8>);
typedef _WorkspaceFstatDart = int Function(int, Pointer<Uint8>);
typedef _WorkspaceUidNative = Uint32 Function();
typedef _WorkspaceUidDart = int Function();

Never _unsafeWorkspaceRoot() => throw const FfmpegException(
  FfmpegErrorCode.executionFailed,
  'Native workspace ownership, private permissions, or lock identity could '
  'not be proven.',
);

int get _workspaceUid => DynamicLibrary.process()
    .lookupFunction<_WorkspaceUidNative, _WorkspaceUidDart>('geteuid')();

bool get _appleWorkspace => Platform.isMacOS || Platform.isIOS;

int _openWorkspaceEntity(
  String name, {
  bool directory = false,
  bool create = false,
}) {
  if (!Platform.isLinux && !Platform.isAndroid && !_appleWorkspace) {
    _unsafeWorkspaceRoot();
  }
  final value = name.toNativeUtf8();
  final noFollow = _appleWorkspace ? 0x0100 : 0x20000;
  final closeOnExec = _appleWorkspace ? 0x1000000 : 0x80000;
  final nonBlocking = _appleWorkspace ? 0x0004 : 0x0800;
  final directoryFlag = _appleWorkspace ? 0x100000 : 0x10000;
  final createFlag = _appleWorkspace ? 0x0200 : 0x0040;
  try {
    final fd =
        DynamicLibrary.process()
            .lookupFunction<_WorkspaceOpenNative, _WorkspaceOpenDart>('open')(
          value,
          noFollow |
              closeOnExec |
              nonBlocking |
              (directory ? directoryFlag : 2) |
              (create ? createFlag : 0),
          0x180, // 0600, only used for atomic lock creation; never O_TRUNC.
        );
    if (fd < 0) _unsafeWorkspaceRoot();
    return fd;
  } finally {
    malloc.free(value);
  }
}

({int mode, int uid, int links}) _workspaceMetadata(int fd) {
  // stat's public ABI differs between Darwin, Linux x86_64 and the other
  // supported Linux/Android ABIs. Only mode/uid/nlink are consumed. The
  // allocation exceeds every supported stat structure, without guessing its
  // complete layout or reading timestamps/padding as identity.
  final buffer = calloc<Uint8>(512);
  try {
    final result = DynamicLibrary.process()
        .lookupFunction<_WorkspaceFstatNative, _WorkspaceFstatDart>(
          // Intel macOS keeps the legacy stat ABI under the unsuffixed
          // symbol; match the SDK's 64-bit inode declaration explicitly.
          Abi.current() == Abi.macosX64 ? r'fstat$INODE64' : 'fstat',
        )(fd, buffer);
    if (result != 0) _unsafeWorkspaceRoot();
    final bytes = ByteData.sublistView(buffer.asTypedList(512));
    final abi = Abi.current();
    // Explicit public stat ABIs selected by the locked native engines; never
    // interpret an unrecognized ABI using another architecture's layout.
    if (!const {
      Abi.macosArm64,
      Abi.macosX64,
      Abi.iosArm64,
      Abi.iosX64,
      Abi.linuxArm64,
      Abi.linuxX64,
      Abi.androidArm,
      Abi.androidArm64,
      Abi.androidIA32,
      Abi.androidX64,
    }.contains(abi)) {
      _unsafeWorkspaceRoot();
    }
    final x64 = abi == Abi.linuxX64 || abi == Abi.androidX64;
    return (
      mode: _appleWorkspace
          ? bytes.getUint16(4, Endian.host)
          : bytes.getUint32(x64 ? 24 : 16, Endian.host),
      uid: bytes.getUint32(_appleWorkspace ? 16 : (x64 ? 28 : 24), Endian.host),
      links: _appleWorkspace
          ? bytes.getUint16(6, Endian.host)
          : x64
          ? bytes.getUint64(16, Endian.host)
          : bytes.getUint32(20, Endian.host),
    );
  } finally {
    calloc.free(buffer);
  }
}

void _requireWorkspaceDirectory(String name, {required bool private}) {
  if (Platform.isWindows) {
    // Windows workspace utilities retain their existing inherited app ACL
    // contract. Do not infer Unix ownership from Dart's synthetic mode bits.
    // The public runtime still rejects Windows before creating workspaces.
    if (FileSystemEntity.typeSync(name, followLinks: false) !=
        FileSystemEntityType.directory) {
      _unsafeWorkspaceRoot();
    }
    return;
  }
  final fd = _openWorkspaceEntity(name, directory: true);
  try {
    final info = _workspaceMetadata(fd);
    if (info.mode & 0xf000 != 0x4000) _unsafeWorkspaceRoot();
    if (private) {
      if (info.uid != _workspaceUid || info.mode & 0x3f != 0) {
        _unsafeWorkspaceRoot();
      }
    } else if ((info.uid != 0 && info.uid != _workspaceUid) ||
        (info.mode & 0x12 != 0 && !(info.uid == 0 && info.mode & 0x200 != 0))) {
      _unsafeWorkspaceRoot();
    }
  } finally {
    _closeFilePosix(fd);
  }
}

Future<Directory> _canonicalTrustedWorkspaceRoot(Directory root) async {
  final normalized = path.normalize(root.path);
  final parent = await Directory(
    path.dirname(normalized),
  ).resolveSymbolicLinks();
  var ancestor = parent;
  while (true) {
    _requireWorkspaceDirectory(ancestor, private: false);
    final next = path.dirname(ancestor);
    if (next == ancestor) break;
    ancestor = next;
  }
  return Directory(path.join(parent, path.basename(normalized)));
}

bool _mkdirPrivateWorkspaceRoot(String name) {
  if (Platform.isWindows) {
    if (FileSystemEntity.typeSync(name, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    try {
      Directory(name).createSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
  final value = name.toNativeUtf8();
  try {
    return DynamicLibrary.process()
            .lookupFunction<_WorkspaceMkdirNative, _WorkspaceMkdirDart>(
              'mkdir',
            )(
          value,
          0x1c0, // 0700 at creation; never chmod/adopt an existing root.
        ) ==
        0;
  } finally {
    malloc.free(value);
  }
}

void _requireOwnedWorkspaceFile(String name) {
  if (Platform.isWindows) {
    final handle = _openRegularFileWindows(name);
    if (_isInvalidWindowsHandle(handle)) _unsafeWorkspaceRoot();
    try {
      if (!_isRegularWindowsHandle(handle)) _unsafeWorkspaceRoot();
    } finally {
      _closeHandleWindows(handle);
    }
    return;
  }
  final fd = _openWorkspaceEntity(name);
  try {
    _requireOwnedWorkspaceDescriptor(fd);
  } finally {
    _closeFilePosix(fd);
  }
}

void _requireOwnedWorkspaceDescriptor(int fd) {
  final info = _workspaceMetadata(fd);
  if (info.mode & 0xf000 != 0x8000 ||
      info.uid != _workspaceUid ||
      info.mode & 0x12 != 0 ||
      info.links != 1) {
    _unsafeWorkspaceRoot();
  }
}

Future<RandomAccessFile> _openWorkspaceLock(
  String name, {
  required bool create,
}) async {
  if (Platform.isWindows) {
    if (create &&
        FileSystemEntity.typeSync(name, followLinks: false) ==
            FileSystemEntityType.notFound) {
      File(name).createSync(exclusive: true);
    }
    _requireOwnedWorkspaceFile(name);
    return File(name).open(mode: FileMode.append);
  }
  final fd = _openWorkspaceEntity(name, create: create);
  try {
    _requireOwnedWorkspaceDescriptor(fd);
    // Linux permits reopening the checked descriptor. Darwin's fdescfs rejects
    // Dart's O_CREAT append open, so use the checked path there: its entire
    // ancestry and private root have already excluded other uid mutations.
    // Append never truncates existing bytes; no payload is written to locks.
    final descriptor = Platform.isLinux || Platform.isAndroid
        ? '/proc/self/fd/$fd'
        : name;
    return await File(descriptor).open(mode: FileMode.append);
  } finally {
    _closeFilePosix(fd);
  }
}

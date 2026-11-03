part of 'io_workspace.dart';

const String _publicationPrefix = '.ii-publication-';
const String _publicationSuffix = '.json';
const int _publicationSchema = 1;
const int _maxPublicationPathBytes = 2048;

extension on IoWorkspace {
  Future<void> _copyToDestination(
    File source,
    String destination, {
    required bool overwrite,
    required FfmpegExecutionContext context,
  }) async {
    IoWorkspace._checkCancellation(context);
    final target = File(path.normalize(File(destination).absolute.path));
    if (utf8.encode(target.path).length > _maxPublicationPathBytes ||
        Platform.isWindows) {
      throw const FfmpegException(
        FfmpegErrorCode.unsupportedPlatform,
        'Crash-safe destination publication is unavailable for this path or '
        'platform.',
      );
    }
    if (!overwrite && await target.exists()) {
      throw FfmpegException(
        FfmpegErrorCode.outputExists,
        'Refusing to overwrite ${target.path}.',
      );
    }
    await target.parent.create(recursive: true);
    final token = IoWorkspace._randomToken();
    final partial = File('${target.path}.ii-$token.partial');
    final journal = File(
      path.join(directory.path, '$_publicationPrefix$token$_publicationSuffix'),
    );
    final record = <String, Object?>{
      'schema': _publicationSchema,
      'owner': IoWorkspace._owner,
      'root_token': _rootToken,
      'workspace_token': _token,
      'workspace_id': path.basename(directory.path),
      'token': token,
      'target_path': target.path,
      'partial_path': partial.path,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    final encodedRecord = jsonEncode(record);
    if (utf8.encode(encodedRecord).length > _maxMarkerBytes) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'The destination path is too long for a recoverable publication.',
      );
    }
    await journal.create(exclusive: true);
    await journal.writeAsString(encodedRecord, flush: true);
    try {
      await partial.create(exclusive: true);
      await IoWorkspace._copyFileCancellable(source, partial, context);
      IoWorkspace._checkCancellation(context);
      if (overwrite) {
        await partial.rename(target.path);
      } else {
        await _installNoReplace(partial, target);
      }
      context.recordPersistentOutputCommit();
    } on FileSystemException catch (error) {
      if (!overwrite && await target.exists()) {
        throw FfmpegException(
          FfmpegErrorCode.outputExists,
          'Refusing to overwrite ${target.path}.',
          cause: error,
        );
      }
      rethrow;
    } finally {
      final cleaned = await _recoverPublicationJournals(directory, {
        'owner': IoWorkspace._owner,
        'token': _token,
        'root_token': _rootToken,
        'workspace_id': path.basename(directory.path),
      });
      if (!cleaned && !context.persistentOutputCommitted) {
        throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'Destination publication cleanup failed; its owned workspace was '
          'preserved for recovery.',
        );
      }
    }
  }

  static Future<void> _installNoReplace(File source, File target) async {
    final installed = _linkFileNoReplacePosix(source.path, target.path);
    if (!installed) {
      throw FileSystemException(
        'Could not atomically install output without replacing a file.',
        target.path,
      );
    }
  }
}

Future<bool> _recoverPublicationJournals(
  Directory workspace,
  Map<String, Object?> workspaceRecord,
) async {
  final journals = <File>[];
  await for (final entity in workspace.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (!name.startsWith(_publicationPrefix) ||
        !name.endsWith(_publicationSuffix)) {
      continue;
    }
    if (entity is! File || journals.isNotEmpty) return false;
    journals.add(entity);
  }
  for (final journal in journals) {
    Map<String, Object?> record;
    try {
      record = await IoWorkspace._readMarker(journal);
    } on Object {
      return false;
    }
    if (!_validPublicationRecord(workspace, journal, record, workspaceRecord)) {
      return false;
    }
    final partial = File(record['partial_path']! as String);
    final type = await FileSystemEntity.type(partial.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      if (await partial.length() > _maxRecoverableWorkspaceBytes) return false;
      try {
        await partial.delete();
      } on FileSystemException {
        return false;
      }
    } else if (type != FileSystemEntityType.notFound) {
      return false;
    }
    try {
      await journal.delete();
    } on FileSystemException {
      return false;
    }
  }
  return true;
}

bool _validPublicationRecord(
  Directory workspace,
  File journal,
  Map<String, Object?> record,
  Map<String, Object?> workspaceRecord,
) {
  final token = record['token'];
  final target = record['target_path'];
  final partial = record['partial_path'];
  final createdRaw = record['created_at'];
  final created = createdRaw is String ? DateTime.tryParse(createdRaw) : null;
  if (token is! String ||
      !_tokenPattern.hasMatch(token) ||
      target is! String ||
      partial is! String ||
      utf8.encode(target).length > _maxPublicationPathBytes ||
      utf8.encode(partial).length > _maxPublicationPathBytes + 64 ||
      !path.isAbsolute(target) ||
      !path.isAbsolute(partial) ||
      target != path.normalize(target) ||
      partial != '$target.ii-$token.partial' ||
      path.basename(journal.path) !=
          '$_publicationPrefix$token$_publicationSuffix' ||
      created == null ||
      created.isAfter(DateTime.now().toUtc())) {
    return false;
  }
  return record['schema'] == _publicationSchema &&
      record['owner'] == IoWorkspace._owner &&
      record['owner'] == workspaceRecord['owner'] &&
      record['root_token'] == workspaceRecord['root_token'] &&
      record['workspace_token'] == workspaceRecord['token'] &&
      record['workspace_id'] == workspaceRecord['workspace_id'] &&
      record['workspace_id'] == path.basename(workspace.path);
}

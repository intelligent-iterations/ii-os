import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../configuration.dart';
import '../backend.dart';
import '../exception.dart';
import '../execution_constraints.dart';
import '../job.dart';

part 'io_workspace_path_reader.dart';
part 'io_workspace_publication.dart';
part 'io_workspace_recovery.dart';

final class IoWorkspace {
  IoWorkspace._(this.directory, this._token, this._rootToken, this._lock);

  static const String _markerName = '.ii-disposable-owner';
  static const String _lockName = '.ii-active-lock';
  static const String _owner = 'ii-ffmpeg-universal';

  final Directory directory;
  final String _token;
  final String _rootToken;
  final RandomAccessFile _lock;

  static Future<IoWorkspace> create(String jobId, {Directory? root}) async {
    final ownedRoot = await _prepareWorkspaceRoot(
      root ?? _defaultWorkspaceRoot(),
    );
    final token = _randomToken();
    final directory = await ownedRoot.directory.createTemp(
      'ii_ffmpeg_universal_${_safeId(jobId)}_',
    );
    RandomAccessFile? lock;
    try {
      await File(path.join(directory.path, _markerName)).writeAsString(
        jsonEncode({
          'owner': _owner,
          'token': token,
          'root_token': ownedRoot.token,
          'workspace_id': path.basename(directory.path),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'pid': pid,
        }),
        flush: true,
      );
      lock = await File(
        path.join(directory.path, _lockName),
      ).open(mode: FileMode.write);
      await lock.lock(FileLock.exclusive);
      return IoWorkspace._(directory, token, ownedRoot.token, lock);
    } catch (_) {
      // createTemp returned this exact new directory to this invocation, so
      // ownership is known even if persisting the durable marker failed.
      if (lock != null) await lock.close();
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  static Future<Map<String, Object?>> _readMarker(File marker) async {
    final source = await marker.open(mode: FileMode.read);
    late final List<int> bytes;
    try {
      bytes = await source.read(_maxMarkerBytes + 1);
    } finally {
      await source.close();
    }
    if (bytes.length > _maxMarkerBytes) throw const FormatException();
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) throw const FormatException();
    return decoded;
  }

  static Future<int> recoverStale({
    required Directory root,
    Duration minimumAge = _defaultRecoveryAge,
    DateTime? now,
  }) async => (await _prepareWorkspaceRoot(
    root,
    minimumAge: minimumAge,
    now: now,
  )).recovered;

  String filePath(String name) => path.join(directory.path, name);

  Future<Map<String, String>> materializeInputs(
    FfmpegJob job,
    FfmpegSafetyPolicy safety,
    FfmpegExecutionContext context,
  ) async {
    final paths = <String, String>{};
    var totalBytes = 0;
    for (final input in job.inputs) {
      _checkCancellation(context);
      if (input is FfmpegBytesInput) {
        totalBytes += input.bytes.length;
        _checkInputLimits(input.name, input.bytes.length, totalBytes, safety);
        final destination = filePath(input.name);
        await _writeBytesCancellable(File(destination), input.bytes, context);
        paths[input.name] = destination;
      } else if (input is FfmpegPathInput) {
        final file = File(input.path);
        final destination = File(filePath(input.name));
        final copied = await _copyInputBounded(
          file,
          destination,
          maxBytes: min(
            safety.maxInputBytes,
            safety.maxTotalInputBytes - totalBytes,
          ),
          context: context,
        );
        totalBytes += copied;
        paths[input.name] = destination.path;
      }
    }
    return paths;
  }

  Map<String, String> outputPaths(FfmpegJob job) => {
    for (final output in job.outputs) output.name: filePath(output.name),
  };

  Future<Map<String, Uint8List>> collectOutputs(
    FfmpegJob job,
    FfmpegSafetyPolicy safety,
    FfmpegExecutionContext context,
  ) async {
    final captured = <String, Uint8List>{};
    File? destinationSource;
    FfmpegOutput? destinationOutput;
    var totalOutputBytes = 0;
    for (final output in job.outputs) {
      _checkCancellation(context);
      final source = File(filePath(output.name));
      if (!await source.exists()) {
        throw FfmpegException(
          FfmpegErrorCode.executionFailed,
          'FFmpeg did not produce ${output.name}.',
        );
      }
      final length = await source.length();
      totalOutputBytes += length;
      final limit = effectiveOutputLimit(job, output, safety);
      if (length > limit) {
        throw FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          '${output.name} is $length bytes; the limit is $limit.',
        );
      }
      if (totalOutputBytes > safety.maxTotalOutputBytes) {
        throw FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          'Declared outputs exceed the ${safety.maxTotalOutputBytes} byte total limit.',
        );
      }
      if (output.captureBytes) {
        captured[output.name] = await _readFileBounded(
          source,
          maxBytes: limit,
          expectedBytes: length,
          context: context,
        );
      }
      if (output.destinationPath != null) {
        destinationSource = source;
        destinationOutput = output;
      }
    }
    // External publication is the final phase. Every output has already been
    // proven present, bounded, and captured, so a later output cannot make a
    // successful destination mutation look like a failed job. Managed jobs
    // allow one destination because atomic transactions across unrelated
    // filesystems and uncooperative processes do not exist portably.
    if (destinationOutput case final output?) {
      _checkCancellation(context);
      await _copyToDestination(
        destinationSource!,
        output.destinationPath!,
        overwrite: job.overwriteOutput,
        context: context,
      );
    }
    return captured;
  }

  Future<void> dispose() async {
    final marker = File(path.join(directory.path, _markerName));
    Map<String, Object?>? record;
    try {
      record = await _readMarker(marker);
    } on Object {
      record = null;
    }
    if (record?['owner'] != _owner ||
        record?['token'] != _token ||
        record?['root_token'] != _rootToken ||
        record?['workspace_id'] != path.basename(directory.path)) {
      await _lock.close();
      throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'Disposable workspace ownership could not be proven; cleanup stopped.',
      );
    }
    if (!await _recoverPublicationJournals(directory, record!)) {
      await _lock.close();
      throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'Published-output remnants could not be proven safe to remove; the '
        'owned workspace was preserved.',
      );
    }
    await _lock.unlock();
    await _lock.close();
    await directory.delete(recursive: true);
  }

  Future<int> sizeBytes({required int stopAfter}) async {
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      total += await entity.length();
      if (total > stopAfter) return total;
    }
    return total;
  }

  Future<FfmpegException?> outputLimitViolation(
    FfmpegJob job,
    FfmpegSafetyPolicy safety,
  ) async {
    var total = 0;
    for (final output in job.outputs) {
      final entity = File(filePath(output.name));
      if (!await entity.exists()) continue;
      final length = await entity.length();
      final limit = effectiveOutputLimit(job, output, safety);
      if (length > limit) {
        return FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          '${output.name} exceeded its $limit byte limit during generation.',
        );
      }
      total += length;
      if (total > safety.maxTotalOutputBytes) {
        return FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          'Declared outputs exceeded the ${safety.maxTotalOutputBytes} byte '
          'total limit during generation.',
        );
      }
    }
    return null;
  }

  static Future<int> _copyInputBounded(
    File source,
    File destination, {
    required int maxBytes,
    required FfmpegExecutionContext context,
  }) async {
    final sourceType = await FileSystemEntity.type(
      source.path,
      followLinks: false,
    );
    if (sourceType != FileSystemEntityType.file) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Input path must identify a regular non-link file: ${source.path}',
      );
    }
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    var copied = 0;
    try {
      await for (final chunk in _openPathInput(source, context)) {
        _checkCancellation(context);
        copied += chunk.length;
        if (copied > maxBytes) {
          throw FfmpegException(
            FfmpegErrorCode.inputTooLarge,
            'Input changed while copying and exceeded its configured limit.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      return copied;
    } finally {
      await sink.close();
    }
  }

  static Future<void> _writeBytesCancellable(
    File destination,
    List<int> bytes,
    FfmpegExecutionContext context,
  ) async {
    const chunkSize = 64 * 1024;
    final output = await destination.open(mode: FileMode.write);
    try {
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        _checkCancellation(context);
        await output.writeFrom(
          bytes,
          offset,
          min(offset + chunkSize, bytes.length),
        );
      }
      await output.flush();
      _checkCancellation(context);
    } finally {
      await output.close();
    }
  }

  static Future<void> _copyFileCancellable(
    File source,
    File destination,
    FfmpegExecutionContext context,
  ) async {
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    try {
      await for (final chunk in source.openRead()) {
        _checkCancellation(context);
        sink.add(chunk);
      }
      await sink.flush();
      _checkCancellation(context);
    } finally {
      await sink.close();
    }
  }

  static Future<Uint8List> _readFileBounded(
    File source, {
    required int maxBytes,
    required int expectedBytes,
    required FfmpegExecutionContext context,
  }) async {
    if (expectedBytes > maxBytes) {
      throw FfmpegException(
        FfmpegErrorCode.outputTooLarge,
        'Output exceeds its configured limit before capture.',
      );
    }
    final bytes = Uint8List(expectedBytes);
    final input = await source.open(mode: FileMode.read);
    var offset = 0;
    try {
      while (offset < bytes.length) {
        _checkCancellation(context);
        final read = await input.readInto(
          bytes,
          offset,
          min(offset + 64 * 1024, bytes.length),
        );
        if (read == 0) {
          throw const FfmpegException(
            FfmpegErrorCode.executionFailed,
            'Output changed while it was being captured.',
          );
        }
        offset += read;
      }
      _checkCancellation(context);
      if (await input.readByte() != -1) {
        throw FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          'Output changed while reading and exceeded its configured limit.',
        );
      }
      return bytes;
    } finally {
      await input.close();
    }
  }

  static void _checkInputLimits(
    String name,
    int length,
    int total,
    FfmpegSafetyPolicy safety,
  ) {
    if (length > safety.maxInputBytes) {
      throw FfmpegException(
        FfmpegErrorCode.inputTooLarge,
        '$name exceeds the ${safety.maxInputBytes} byte input limit.',
      );
    }
    if (total > safety.maxTotalInputBytes) {
      throw FfmpegException(
        FfmpegErrorCode.inputTooLarge,
        'Inputs exceed the ${safety.maxTotalInputBytes} byte total limit.',
      );
    }
  }

  static void _checkCancellation(FfmpegExecutionContext context) {
    if (!context.isCancelled) return;
    throw _cancellationException(context);
  }

  static FfmpegException _cancellationException(
    FfmpegExecutionContext context,
  ) => FfmpegException(
    context.timedOut ? FfmpegErrorCode.timedOut : FfmpegErrorCode.cancelled,
    context.timedOut
        ? 'The job timed out while preparing inputs.'
        : 'The job was cancelled while preparing inputs.',
  );

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _safeId(String value) =>
      value.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
}

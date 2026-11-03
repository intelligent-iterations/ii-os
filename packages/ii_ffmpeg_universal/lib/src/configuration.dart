import 'dart:convert';

import 'exception.dart';
import 'job.dart';

part 'argument_profile_data.dart';
part 'engine_bundles.dart';

/// Resource and protocol limits applied before a backend sees a job.
final class FfmpegSafetyPolicy {
  static const int maxManagedProbeOutputBytes = 8 * 1024 * 1024;
  static const int maxManagedInputs = 16;
  static const int maxManagedOutputs = 8;
  static const int maxManagedArguments = 256;
  static const int maxManagedArgumentBytes = 16 * 1024;
  static const int maxManagedTotalArgumentBytes = 24 * 1024;

  const FfmpegSafetyPolicy({
    this.maxInputBytes = 512 * 1024 * 1024,
    this.maxOutputBytes = 512 * 1024 * 1024,
    this.maxTotalInputBytes = 512 * 1024 * 1024,
    this.maxTotalOutputBytes = 512 * 1024 * 1024,
    this.maxWorkspaceBytes = 1024 * 1024 * 1024,
    this.maxEngineAllocationBytes = 64 * 1024 * 1024,
    this.maxLogBytes = 1024 * 1024,
    this.maxLogLineBytes = 16 * 1024,
    this.defaultTimeout = const Duration(minutes: 15),
    this.maxTimeout = const Duration(hours: 1),
    this.terminationGracePeriod = const Duration(seconds: 5),
    this.maxDecodedPixels = 33 * 1024 * 1024,
    this.maxBrowserEngineMemoryBytes = 512 * 1024 * 1024,
  });

  final int maxInputBytes;
  final int maxOutputBytes;
  final int maxTotalInputBytes;
  final int maxTotalOutputBytes;
  final int maxWorkspaceBytes;

  /// Native FFmpeg's maximum libavutil allocation block. This is neither a
  /// total heap limit nor an operating-system RSS limit.
  final int maxEngineAllocationBytes;
  final int maxLogBytes;
  final int maxLogLineBytes;
  final Duration defaultTimeout;
  final Duration maxTimeout;
  final Duration terminationGracePeriod;

  /// Maximum dimensions accepted by each decoded video frame.
  final int maxDecodedPixels;

  /// Hard ceiling for ffmpeg.wasm linear-memory growth.
  ///
  /// This does not describe the browser's JavaScript or Dart heaps, whose
  /// package-owned allocations are instead bounded by transfer/workspace
  /// limits.
  final int maxBrowserEngineMemoryBytes;

  void validate(FfmpegJob job) {
    if (job.id.isEmpty ||
        job.id.length > 128 ||
        job.arguments.isEmpty ||
        job.arguments.length > maxManagedArguments ||
        job.inputs.length > maxManagedInputs ||
        job.outputs.length > maxManagedOutputs) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'A job needs a 1-128 character ID, 1-256 arguments, no more than '
        '16 inputs, and no more than 8 outputs.',
      );
    }
    if (job.operation == FfmpegOperation.ffprobe && job.outputs.isEmpty) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'FFprobe jobs must declare at least one output resource.',
      );
    }
    if (job.operation == FfmpegOperation.ffprobe &&
        (job.inputs.length != 1 || job.outputs.length != 1)) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Managed FFprobe jobs require exactly one input and one output.',
      );
    }
    if (maxInputBytes <= 0 ||
        maxOutputBytes <= 0 ||
        maxTotalInputBytes <= 0 ||
        maxTotalOutputBytes <= 0 ||
        maxWorkspaceBytes < maxTotalInputBytes ||
        maxEngineAllocationBytes <= 0 ||
        maxEngineAllocationBytes > 1024 * 1024 * 1024 ||
        maxLogBytes <= 0 ||
        maxLogLineBytes <= 0 ||
        maxLogLineBytes > maxLogBytes ||
        maxDecodedPixels <= 0 ||
        maxDecodedPixels > 128 * 1024 * 1024 ||
        maxBrowserEngineMemoryBytes < 64 * 1024 * 1024 ||
        maxBrowserEngineMemoryBytes > 512 * 1024 * 1024 ||
        terminationGracePeriod <= Duration.zero) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'The FFmpeg safety policy contains invalid resource limits.',
      );
    }

    final names = <String>{};
    final portableNames = <String>{};
    for (final input in job.inputs) {
      _validateResourceName(input.name);
      if (input is FfmpegPathInput) {
        _validateNativePath(input.path, role: 'input');
      }
      if (!names.add(input.name) ||
          !portableNames.add(input.name.toLowerCase())) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          'Resource name ${input.name} is duplicated on a supported platform.',
        );
      }
    }
    for (final output in job.outputs) {
      _validateResourceName(output.name);
      if (output.destinationPath case final destination?) {
        _validateNativePath(destination, role: 'destination');
      }
      if (!names.add(output.name) ||
          !portableNames.add(output.name.toLowerCase())) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          'Resource name ${output.name} is duplicated on a supported platform.',
        );
      }
    }
    if (job.outputs.where((output) => output.destinationPath != null).length >
        1) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'A managed job may publish at most one native destination. Capture '
        'additional outputs as bytes and publish them in a separate operation.',
      );
    }
    var totalByteInputs = 0;
    for (final input in job.inputs) {
      if (input is FfmpegBytesInput && input.bytes.length > maxInputBytes) {
        throw FfmpegException(
          FfmpegErrorCode.inputTooLarge,
          '${input.name} exceeds the $maxInputBytes byte input limit.',
        );
      }
      if (input is FfmpegBytesInput) totalByteInputs += input.bytes.length;
    }
    if (totalByteInputs > maxTotalInputBytes) {
      throw FfmpegException(
        FfmpegErrorCode.inputTooLarge,
        'Declared byte inputs exceed the $maxTotalInputBytes byte total limit.',
      );
    }
    for (final output in job.outputs) {
      final limit = output.maxBytes ?? maxOutputBytes;
      if (limit <= 0 || limit > maxOutputBytes) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          '${output.name} has an invalid output byte limit.',
        );
      }
      if (job.operation == FfmpegOperation.ffprobe &&
          output.maxBytes != null &&
          limit > maxManagedProbeOutputBytes) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          'Managed FFprobe output is capped at '
          '$maxManagedProbeOutputBytes bytes.',
        );
      }
    }
    final timeout = job.timeout ?? defaultTimeout;
    if (timeout <= Duration.zero || timeout > maxTimeout) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Timeout must be positive and no longer than $maxTimeout.',
      );
    }
    var totalArgumentCodeUnits = 0;
    var totalArgumentUtf8Bytes = 0;
    for (final argument in job.arguments) {
      final argumentUtf8Bytes = utf8.encode(argument).length;
      totalArgumentCodeUnits += argument.length + 1;
      totalArgumentUtf8Bytes += argumentUtf8Bytes + 1;
      if (argument.contains('\u0000') ||
          argument.length > maxManagedArgumentBytes ||
          argumentUtf8Bytes > maxManagedArgumentBytes) {
        throw const FfmpegException(
          FfmpegErrorCode.unsafeArgument,
          'FFmpeg arguments may not contain NUL bytes or exceed 16 KiB.',
        );
      }
      if (_containsManagedProtocol(argument)) {
        throw FfmpegException(
          FfmpegErrorCode.unsafeArgument,
          'Protocol input is disabled by policy: $argument',
        );
      }
    }
    if (totalArgumentCodeUnits > maxManagedTotalArgumentBytes ||
        totalArgumentUtf8Bytes > maxManagedTotalArgumentBytes) {
      throw const FfmpegException(
        FfmpegErrorCode.unsafeArgument,
        'The complete FFmpeg argument list may not exceed 24 KiB.',
      );
    }
    _validateManagedArguments(job);
  }

  static void _validateResourceName(String value) {
    final windowsStem = value.split('.').first.toLowerCase();
    if (!_resourcePattern.hasMatch(value) ||
        value == '.' ||
        value == '..' ||
        value.endsWith('.') ||
        _windowsReservedNames.contains(windowsStem)) {
      throw FfmpegException(
        FfmpegErrorCode.invalidResourceName,
        'Resource names must be portable base names: $value',
      );
    }
  }

  static void _validateNativePath(String value, {required String role}) {
    if (value.isEmpty || value.contains('\u0000')) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Native $role paths must be non-empty and contain no NUL bytes.',
      );
    }
    final normalized = value.replaceAll(r'\', '/');
    final lower = normalized.toLowerCase();
    if (lower.startsWith('//') || lower.startsWith('/device/')) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Native $role UNC and device namespace paths are disabled.',
      );
    }
    if (RegExp(r'^[A-Za-z]:[^/]').hasMatch(normalized)) {
      throw FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Native $role drive-relative paths are disabled.',
      );
    }
    final components = normalized.split('/').where((part) => part.isNotEmpty);
    var index = 0;
    for (final component in components) {
      final isDrive = index == 0 && RegExp(r'^[A-Za-z]:$').hasMatch(component);
      index += 1;
      if (isDrive || component == '.' || component == '..') continue;
      final stem = component.split('.').first.toLowerCase();
      if (component.contains(':') ||
          component.endsWith('.') ||
          component.endsWith(' ') ||
          _windowsReservedNames.contains(stem)) {
        throw FfmpegException(
          FfmpegErrorCode.invalidJob,
          'Native $role path contains a device, stream, or non-portable '
          'component: $component',
        );
      }
    }
  }

  static bool _containsManagedProtocol(String value) =>
      !_windowsDrivePattern.hasMatch(value) && _protocolPattern.hasMatch(value);

  static void _validateManagedArguments(FfmpegJob job) {
    final inputNames = {for (final input in job.inputs) input.name};
    final outputNames = {for (final output in job.outputs) output.name};
    final referencedInputs = <String>{};
    final referencedOutputs = <String>{};
    String? pendingFormat;
    var jsonProbeOutput = false;
    var boundedProbeEntries = false;
    for (var index = 0; index < job.arguments.length; index += 1) {
      final argument = job.arguments[index];
      if (argument == '-') {
        if (job.operation == FfmpegOperation.ffmpeg &&
            pendingFormat == 'null') {
          pendingFormat = null;
          continue;
        }
        throw const FfmpegException(
          FfmpegErrorCode.unsafeArgument,
          'Managed standard-stream output is allowed only for the null muxer.',
        );
      }
      if (!argument.startsWith('-')) {
        if (job.operation == FfmpegOperation.ffmpeg &&
            outputNames.contains(argument)) {
          final format = pendingFormat;
          if (format == null || !_safeOutputFormats.contains(format)) {
            throw FfmpegException(
              FfmpegErrorCode.unsafeArgument,
              'Managed outputs require an explicit allowlisted -f format: '
              '$argument',
            );
          }
          referencedOutputs.add(argument);
          pendingFormat = null;
          continue;
        }
        throw FfmpegException(
          FfmpegErrorCode.unsafeArgument,
          'Unmanaged positional FFmpeg argument is disabled: $argument',
        );
      }
      if (_flagOptions.contains(argument)) continue;
      final managedOption = _managedValueOption(argument);
      if (managedOption == null || index + 1 >= job.arguments.length) {
        throw FfmpegException(
          FfmpegErrorCode.unsafeArgument,
          'FFmpeg option is not in the managed argument profile: $argument',
        );
      }
      final value = job.arguments[++index];
      if (managedOption == '-i') {
        if (pendingFormat == 'lavfi') {
          if (!_safeLavfiSourcePattern.hasMatch(value)) {
            throw FfmpegException(
              FfmpegErrorCode.unsafeArgument,
              'Managed lavfi inputs require an allowlisted generated source: '
              '$value',
            );
          }
        } else if (!inputNames.contains(value)) {
          throw FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Managed input options must reference a declared resource.',
          );
        } else if (pendingFormat == null ||
            !_safeInputFormats.contains(pendingFormat)) {
          throw FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Managed file inputs require an explicit allowlisted -f format: '
            '$value',
          );
        } else {
          referencedInputs.add(value);
        }
        pendingFormat = null;
      } else if (managedOption == '-o') {
        if (job.operation != FfmpegOperation.ffprobe ||
            !outputNames.contains(value)) {
          throw const FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Managed FFprobe output must reference a declared resource.',
          );
        }
        referencedOutputs.add(value);
      } else {
        if (inputNames.contains(value) || outputNames.contains(value)) {
          throw const FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Declared resources may only appear in their managed input or '
            'output role.',
          );
        }
        _validateLiteral(value);
        if (managedOption == '-filter:v' ||
            managedOption == '-filter:a' ||
            managedOption == '-filter_complex') {
          _validateFilterGraph(value);
        }
      }
      if (managedOption == '-show_entries') {
        if (!_validateProbeEntries(value)) {
          throw const FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Managed FFprobe show entries include an unbounded field.',
          );
        }
        boundedProbeEntries = true;
      }
      if (managedOption == '-of') {
        jsonProbeOutput = value.toLowerCase() == 'json';
      }
      if (managedOption == '-f') {
        final format = value.toLowerCase();
        if (_blockedFormats.contains(format)) {
          throw FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'The $format format can create unmanaged files and is disabled.',
          );
        }
        pendingFormat = format;
      }
    }
    if (!referencedInputs.containsAll(inputNames) ||
        !referencedOutputs.containsAll(outputNames)) {
      throw const FfmpegException(
        FfmpegErrorCode.invalidJob,
        'Every declared resource must be referenced in its managed role.',
      );
    }
    if (job.operation == FfmpegOperation.ffprobe && !jsonProbeOutput) {
      throw const FfmpegException(
        FfmpegErrorCode.unsafeArgument,
        'Managed FFprobe jobs require JSON output.',
      );
    }
    if (job.operation == FfmpegOperation.ffprobe && !boundedProbeEntries) {
      throw const FfmpegException(
        FfmpegErrorCode.unsafeArgument,
        'Managed FFprobe jobs require allowlisted bounded show entries.',
      );
    }
  }

  static bool _validateProbeEntries(String value) {
    final sections = value.split(':');
    if (sections.isEmpty) return false;
    for (final section in sections) {
      final separator = section.indexOf('=');
      if (separator <= 0 || separator == section.length - 1) return false;
      final name = section.substring(0, separator);
      final allowed = _safeProbeEntries[name];
      if (allowed == null) return false;
      final fields = section.substring(separator + 1).split(',');
      if (fields.any((field) => field.isEmpty || !allowed.contains(field))) {
        return false;
      }
    }
    return true;
  }

  static String? _managedValueOption(String value) {
    if (_valueOptions.contains(value)) return value;
    for (final option in _indexedStreamOptions) {
      final prefix = '$option:';
      if (!value.startsWith(prefix)) continue;
      final streamIndex = value.substring(prefix.length);
      return _streamIndexPattern.hasMatch(streamIndex) ? option : null;
    }
    return null;
  }

  static void _validateFilterGraph(String value) {
    if (_filterFileOptionPattern.hasMatch(value)) {
      throw const FfmpegException(
        FfmpegErrorCode.unsafeArgument,
        'Managed filters may not read or write side files.',
      );
    }
    for (final segment in _splitFilterGraph(value)) {
      var remainder = segment.trimLeft();
      while (remainder.startsWith('[')) {
        final end = remainder.indexOf(']');
        if (end <= 1) {
          throw const FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Managed filter graph labels are malformed.',
          );
        }
        remainder = remainder.substring(end + 1).trimLeft();
      }
      final match = _filterNamePattern.firstMatch(remainder);
      final name = match?.group(1)?.toLowerCase();
      if (name == null || !_safeFilters.contains(name)) {
        throw FfmpegException(
          FfmpegErrorCode.unsafeArgument,
          'Filter ${name ?? remainder} is not in the managed filter profile.',
        );
      }
    }
  }

  static List<String> _splitFilterGraph(String value) {
    final parts = <String>[];
    var start = 0;
    String? quote;
    var escaped = false;
    for (var index = 0; index < value.length; index += 1) {
      final character = value[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (character == quote) quote = null;
        continue;
      }
      if (character == "'" || character == '"') {
        quote = character;
        continue;
      }
      if (character == ',' || character == ';') {
        if (index == start) {
          throw const FfmpegException(
            FfmpegErrorCode.unsafeArgument,
            'Managed filter graphs may not contain empty filters.',
          );
        }
        parts.add(value.substring(start, index));
        start = index + 1;
      }
    }
    if (quote != null || escaped || start == value.length) {
      throw const FfmpegException(
        FfmpegErrorCode.unsafeArgument,
        'Managed filter graph quoting is malformed.',
      );
    }
    parts.add(value.substring(start));
    return parts;
  }

  static void _validateLiteral(String value) {
    if (_windowsDrivePattern.hasMatch(value) ||
        _windowsPathInValuePattern.hasMatch(value) ||
        value.startsWith('/') ||
        value.startsWith('\\\\') ||
        value.contains(r'\:') ||
        value.contains(r'\/') ||
        value.contains(r'\\') ||
        _parentTraversalPattern.hasMatch(value) ||
        _absolutePathInValuePattern.hasMatch(value) ||
        _containsManagedProtocol(value)) {
      throw FfmpegException(
        FfmpegErrorCode.unsafeArgument,
        'Managed FFmpeg values may not reference undeclared files: $value',
      );
    }
  }
}

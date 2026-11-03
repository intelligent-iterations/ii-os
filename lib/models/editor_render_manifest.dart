import 'dart:typed_data';

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';

import 'models.dart';

/// The shape version written into every dispatched render.
const editorRenderManifestVersion = 1;

/// A render described completely enough that a workspace machine runs exactly
/// what this device would have run.
///
/// The editor compiles a timeline into one FFmpeg invocation. Sending the
/// timeline instead would mean a second compiler on the runner, and two
/// compilers drift; sending the invocation means the runner and the browser
/// produce the same video from the same arguments. The runner still validates
/// those arguments against the same allowlist before running them, so a
/// tampered manifest is refused rather than executed.
final class EditorRenderManifest {
  const EditorRenderManifest({
    required this.arguments,
    required this.inputs,
    required this.outputName,
    required this.mediaType,
    required this.expectedDuration,
    required this.maxOutputBytes,
  });

  factory EditorRenderManifest.fromJson(JsonMap json) {
    if (json['version'] != editorRenderManifestVersion) {
      throw const FormatException(
        'This render was described by a different version of the editor.',
      );
    }
    return EditorRenderManifest(
      arguments: [
        for (final value in json['arguments'] as List<Object?>? ?? const [])
          '$value',
      ],
      inputs: [
        for (final value in json['inputs'] as List<Object?>? ?? const [])
          EditorRenderInput.fromJson(asJsonMap(value)),
      ],
      outputName: '${json['outputName']}',
      mediaType: '${json['mediaType']}',
      expectedDuration: Duration(
        microseconds: (json['expectedDurationMicros'] as num? ?? 0).toInt(),
      ),
      maxOutputBytes: (json['maxOutputBytes'] as num? ?? 0).toInt(),
    );
  }

  final List<String> arguments;
  final List<EditorRenderInput> inputs;
  final String outputName;
  final String mediaType;
  final Duration expectedDuration;
  final int maxOutputBytes;

  JsonMap toJson() => {
    'version': editorRenderManifestVersion,
    'arguments': arguments,
    'inputs': [for (final input in inputs) input.toJson()],
    'outputName': outputName,
    'mediaType': mediaType,
    'expectedDurationMicros': expectedDuration.inMicroseconds,
    'maxOutputBytes': maxOutputBytes,
  };

  /// Rebuilds the job with bytes the runner fetched, so the runner validates
  /// and executes through the same code path the browser does.
  FfmpegJob toJob(Map<String, Uint8List> bytesByName) {
    final missing = [
      for (final input in inputs)
        if (!bytesByName.containsKey(input.name)) input.name,
    ];
    if (missing.isNotEmpty) {
      throw FormatException(
        'The render is missing input bytes for ${missing.join(', ')}.',
      );
    }
    for (final input in inputs) {
      if (bytesByName[input.name]!.length != input.byteLength) {
        throw FormatException(
          'Input ${input.name} did not arrive at its declared size.',
        );
      }
    }
    return FfmpegJob(
      id: 'editor-render',
      arguments: arguments,
      inputs: [
        for (final input in inputs)
          FfmpegBytesInput(input.name, bytesByName[input.name]!),
      ],
      outputs: [FfmpegOutput(outputName, maxBytes: maxOutputBytes)],
      expectedDuration: expectedDuration,
    );
  }
}

/// One file the render reads, and where the workspace keeps it.
final class EditorRenderInput {
  const EditorRenderInput({
    required this.name,
    required this.assetId,
    required this.byteLength,
  });

  factory EditorRenderInput.fromJson(JsonMap json) => EditorRenderInput(
    name: '${json['name']}',
    assetId: '${json['assetId']}',
    byteLength: (json['byteLength'] as num? ?? 0).toInt(),
  );

  /// The filename the arguments refer to, such as `input-0.mp4`.
  final String name;

  /// The workspace source asset holding those bytes.
  final String assetId;
  final int byteLength;

  JsonMap toJson() => {
    'name': name,
    'assetId': assetId,
    'byteLength': byteLength,
  };
}

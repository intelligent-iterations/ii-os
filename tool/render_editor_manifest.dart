@TestOn('vm')
library;

/// Runs an editor export on a machine that is not the browser.
///
/// The workspace machine is handed the render the editor already compiled, so
/// there is no second compiler here to drift from the one people are watching
/// while they edit. Everything this reads is named by the manifest; nothing
/// here knows what a timeline is.
///
/// It is shaped as a test because `ii_ffmpeg_universal` is a Flutter package
/// and `flutter test` is the only way to run one headlessly:
///
/// ```bash
/// II_RENDER_MANIFEST=/path/manifest.json \
/// II_RENDER_INPUT_DIR=/path/inputs \
/// II_RENDER_OUTPUT=/path/output.mp4 \
///   flutter test tool/render_editor_manifest.dart
/// ```
///
/// Inputs must already be in `II_RENDER_INPUT_DIR` under the names the
/// manifest gives them. Fetching them is the workflow's job, because only the
/// workflow holds the token that authorizes reading a workspace asset.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_os/models/editor_render_manifest.dart';
import 'package:ii_os/services/editor_manifest_renderer.dart';

import '../test/desktop_engine.dart';
import 'render_editor_manifest_policy.dart';

void main() {
  testWidgets(
    'renders the manifest this machine was given',
    (tester) async => tester.runAsync(_render),
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _render() async {
  final manifest = EditorRenderManifest.fromJson(
    jsonDecode(await File(_required('II_RENDER_MANIFEST')).readAsString())
        as Map<String, Object?>,
  );
  final inputDirectory = Directory(_required('II_RENDER_INPUT_DIR'));
  final destination = File(_required('II_RENDER_OUTPUT'));
  final inputs = <String, Uint8List>{};
  for (final input in manifest.inputs) {
    final file = renderInputFile(inputDirectory, input.name);
    if (!await file.exists()) {
      throw StateError('The render input ${input.name} was not delivered.');
    }
    inputs[input.name] = await file.readAsBytes();
  }

  final safety = FfmpegSafetyPolicy(
    maxOutputBytes: manifest.maxOutputBytes,
    maxTotalOutputBytes: manifest.maxOutputBytes,
    defaultTimeout: renderTimeoutFor(manifest.expectedDuration),
    maxTimeout: const Duration(minutes: 30),
  );
  // The engine insists on creating its own workspace root, so it is handed a
  // path inside a directory this run owns rather than one already made here.
  final owned = await Directory.systemTemp.createTemp('ii-os-render-');
  final engine = UniversalFfmpeg(
    configuration: FfmpegConfiguration(
      safety: safety,
      desktopBundle: await resolveDesktopBundle(),
      nativeWorkspaceRoot: owned.uri.resolve('workspaces').toFilePath(),
    ),
  );
  try {
    final bytes = await renderEditorManifest(
      manifest: manifest,
      inputs: inputs,
      engine: engine,
      safety: safety,
    );
    await destination.writeAsBytes(bytes, flush: true);
    stdout.writeln(
      'rendered ${bytes.length} bytes of ${manifest.mediaType} '
      'to ${destination.path}',
    );
  } on EditorManifestRenderFailure catch (failure) {
    for (final line in failure.logs) {
      stderr.writeln(line);
    }
    rethrow;
  } finally {
    await engine.dispose();
    await owned.delete(recursive: true);
  }
}

String _required(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) throw StateError('$name is required.');
  return value;
}

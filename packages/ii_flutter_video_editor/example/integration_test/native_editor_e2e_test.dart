@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:integration_test/integration_test.dart';

const _manifestSha256 = String.fromEnvironment(
  'II_FFMPEG_DESKTOP_MANIFEST_SHA256',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'packaged native editor splits, captions, and renders a real MP4',
    (tester) async {
      final state = await _OwnedNativeState.create();
      const safety = FfmpegSafetyPolicy(
        maxInputBytes: 16 * 1024 * 1024,
        maxOutputBytes: 16 * 1024 * 1024,
        maxTotalInputBytes: 16 * 1024 * 1024,
        maxTotalOutputBytes: 16 * 1024 * 1024,
        maxWorkspaceBytes: 48 * 1024 * 1024,
        defaultTimeout: Duration(minutes: 2),
        maxTimeout: Duration(minutes: 3),
      );
      final engine = UniversalFfmpeg(
        configuration: FfmpegConfiguration(
          safety: safety,
          desktopBundle: await _desktopBundle(),
          nativeWorkspaceRoot: Platform.isMacOS
              ? state.directory.uri.resolve('workspaces').toFilePath()
              : null,
        ),
      );
      try {
        final seedResult = await engine.execute(
          FfmpegJob(
            id: 'native-editor-seed',
            arguments: const [
              '-f',
              'lavfi',
              '-i',
              'color=c=black:s=96x64:r=10:d=0.4',
              '-c:v',
              'mpeg4',
              '-frames:v',
              '4',
              '-f',
              'mp4',
              'seed.mp4',
            ],
            outputs: const [FfmpegOutput('seed.mp4')],
            expectedDuration: const Duration(milliseconds: 400),
          ),
        );
        expect(
          seedResult.isSuccess,
          isTrue,
          reason: seedResult.logs.join('\n'),
        );
        final seedBytes = seedResult.outputBytes['seed.mp4']!;
        final seed = MediaSource(
          id: 'editor-seed-video',
          byteLength: seedBytes.length,
          fileExtension: 'mp4',
          openRead: () => Stream<List<int>>.value(seedBytes),
        );
        final project = EditorProject(
          id: 'native-editor-project',
          width: 96,
          height: 64,
          framesPerSecond: 10,
          duration: MediaTime.seconds(0.2),
          output: const MediaOutputSettings(
            videoCodec: MediaVideoCodec.mpeg4,
            audioCodec: MediaAudioCodec.aac,
            videoBitrate: 100000,
            audioBitrate: 32000,
          ),
          lanes: [
            EditorLane(
              id: 'native-video-lane',
              label: 'Video',
              kind: EditorLaneKind.video,
              clips: [
                EditorVideoClip(
                  id: 'native-video-clip',
                  timelineStart: MediaTime.zero,
                  duration: MediaTime.seconds(0.2),
                  source: seed,
                  sourceRange: MediaRange(
                    start: MediaTime.zero,
                    duration: MediaTime.seconds(0.2),
                  ),
                  fit: MediaFit.fill,
                ),
              ],
            ),
            EditorLane(
              id: 'native-caption-lane',
              label: 'Captions',
              kind: EditorLaneKind.captions,
              clips: [
                EditorCaptionClip(
                  id: 'native-caption-clip',
                  timelineStart: MediaTime.zero,
                  duration: MediaTime.seconds(0.2),
                  text: 'LOCAL',
                  destination: const MediaRect(x: 0, y: 0, width: 1, height: 1),
                  style: const EditorCaptionStyle(
                    fontSize: 18,
                    horizontalPadding: 2,
                    verticalPadding: 2,
                    backgroundColor: 0x00000000,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ],
        );
        final split = splitEditorClip(
          project: project,
          selection: const EditorSelection(
            laneId: 'native-video-lane',
            clipId: 'native-video-clip',
          ),
          at: MediaTime.seconds(0.1),
        );
        expect(split.project.lanes.first.clips, hasLength(2));

        final plan = await const EditorCompositionCompiler().compile(
          split.project,
          safety: safety,
          mediaLimits: const MediaLimits(
            maxInputBytes: 16 * 1024 * 1024,
            maxSourceBytes: 16 * 1024 * 1024,
            maxOutputBytes: 16 * 1024 * 1024,
          ),
        );
        final rendered = await engine.execute(plan.job);
        expect(rendered.isSuccess, isTrue, reason: rendered.logs.join('\n'));
        final bytes = rendered.outputBytes[plan.outputName]!;
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.skip(4).take(4)), 'ftyp');

        final frameResult = await engine.execute(
          FfmpegJob(
            id: 'native-editor-frame',
            arguments: const [
              '-ss',
              '0.1',
              '-f',
              'mov',
              '-i',
              'edited.mp4',
              '-frames:v',
              '1',
              '-f',
              'image2',
              'frame.png',
            ],
            inputs: [FfmpegBytesInput('edited.mp4', bytes)],
            outputs: const [FfmpegOutput('frame.png')],
          ),
        );
        expect(
          frameResult.isSuccess,
          isTrue,
          reason: frameResult.logs.join('\n'),
        );
        final rgba = await _decodeRgba(frameResult.outputBytes['frame.png']!);
        expect(rgba, hasLength(96 * 64 * 4));
        var glyphPixels = 0;
        for (var index = 0; index < rgba.length; index += 4) {
          if (rgba[index] > 170 &&
              rgba[index + 1] > 170 &&
              rgba[index + 2] > 170) {
            glyphPixels++;
          }
        }
        expect(glyphPixels, greaterThan(12));
        expect(glyphPixels, lessThan(96 * 64 ~/ 3));
      } finally {
        await engine.dispose();
        await state.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<FfmpegDesktopBundle?> _desktopBundle() async {
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  if (_manifestSha256.isEmpty) {
    throw StateError('The packaged desktop engine manifest digest is absent.');
  }
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final root = Platform.isMacOS
      ? executableDirectory.parent.uri
            .resolve(
              'Frameworks/App.framework/Resources/flutter_assets/'
              'assets/desktop_engine/',
            )
            .toFilePath()
      : executableDirectory.uri
            .resolve('data/flutter_assets/assets/desktop_engine/')
            .toFilePath();
  return loadAttestedFfmpegDesktopBundle(
    rootPath: root,
    manifestSha256: _manifestSha256,
  );
}

Future<Uint8List> _decodeRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  ui.Image? image;
  try {
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Could not decode the rendered frame.');
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

final class _OwnedNativeState {
  _OwnedNativeState(this.directory, this.owner);

  final Directory directory;
  final String owner;

  static Future<_OwnedNativeState> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'ii-video-editor-native-disposable-',
    );
    final owner =
        'ii-video-editor-native-${DateTime.now().microsecondsSinceEpoch}';
    await File.fromUri(
      directory.uri.resolve('.ii-disposable-owner'),
    ).writeAsString(owner, flush: true);
    return _OwnedNativeState(directory, owner);
  }

  Future<void> dispose() async {
    final marker = File.fromUri(directory.uri.resolve('.ii-disposable-owner'));
    if (!await marker.exists() || await marker.readAsString() != owner) {
      throw StateError(
        'Refusing to clean native state without exact ownership.',
      );
    }
    await directory.delete(recursive: true);
  }
}

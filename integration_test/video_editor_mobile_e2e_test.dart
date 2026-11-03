import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/services/local_document_identity.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/editor_renderer.dart';
import 'package:ii_os/services/local_editor_file_saver.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';
import 'package:ii_os/services/video_editor_project.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ii-os edits and probes media through mobile FFmpegKit',
    (tester) async {
      final ffmpeg = createVideoEditorFfmpeg();
      addTearDown(ffmpeg.dispose);
      await ffmpeg.initialize().timeout(const Duration(seconds: 30));
      expect(ffmpeg.capabilities.backend, 'ffmpeg-kit');

      const sourceName = 'ii-os-mobile-source.mp4';
      final sourceResult = await ffmpeg.execute(
        FfmpegJob(
          id: 'ii-os-mobile-source',
          arguments: const [
            '-f',
            'lavfi',
            '-i',
            'color=c=blue:s=160x90:r=10:d=0.8',
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:duration=0.8',
            '-map',
            '0:v',
            '-map',
            '1:a',
            '-c:v',
            'mpeg4',
            '-c:a',
            'aac',
            '-t',
            '0.8',
            '-f',
            'mp4',
            sourceName,
          ],
          outputs: const [FfmpegOutput(sourceName)],
          expectedDuration: const Duration(milliseconds: 800),
        ),
      );
      final sourceBytes = sourceResult.outputBytes[sourceName];
      expect(
        sourceResult.isSuccess,
        isTrue,
        reason: sourceResult.logs.join('\n'),
      );
      expect(sourceBytes, isNotNull);

      final probe = await probeEditorMedia(
        ffmpeg: ffmpeg,
        id: 'mobile-source-probe',
        bytes: sourceBytes!,
        contentType: 'video/mp4',
      );
      expect(probe.hasVideo, isTrue);
      expect(probe.hasAudio, isTrue);

      final media = LocalEditorMedia(
        id: 'mobile-media',
        filename: sourceName,
        path: '',
        bytes: sourceBytes,
        contentType: 'video/mp4',
        duration: probe.duration,
        hasVideo: probe.hasVideo,
        hasAudio: probe.hasAudio,
        width: probe.width,
        height: probe.height,
      );
      var project = addLocalMediaToNewLanes(
        projectId: 'mobile-editor-project',
        project: null,
        media: media,
        videoLaneId: 'mobile-video-lane',
        audioLaneId: 'mobile-audio-lane',
        videoClipId: 'mobile-video-clip',
        audioClipId: 'mobile-audio-clip',
        linkGroupId: 'mobile-media-pair',
        videoBitrate: 500000,
      );
      final still = await prepareLocalEditorMedia(
        ffmpeg: ffmpeg,
        id: 'mobile-generated-image',
        filename: 'mobile-generated-image.png',
        path: '',
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
          'A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
        expectedContentType: 'image/png',
      );
      expect(still.hasVideo, isTrue);
      expect(still.hasAudio, isFalse);
      expect(still.duration, editorStillImageDuration);
      project = addLocalMediaToNewLanes(
        projectId: project.id,
        project: project,
        media: still,
        videoLaneId: 'mobile-image-lane',
        audioLaneId: 'mobile-image-audio-lane',
        videoClipId: 'mobile-image-clip',
        audioClipId: 'mobile-image-audio-clip',
        videoBitrate: 500000,
      );
      project = splitEditorClip(
        project: project,
        selection: const EditorSelection(
          laneId: 'mobile-video-lane',
          clipId: 'mobile-video-clip',
        ),
        at: MediaTime.seconds(0.4),
      ).project;
      project = addEditorCaption(
        project: project,
        playhead: MediaTime.seconds(0.2),
        laneId: 'mobile-caption-lane',
        clipId: 'mobile-caption-clip',
        text: 'LOCAL MOBILE',
        subtitle: true,
      );

      final renderer = EditorRenderer(
        engine: ffmpeg,
        compiler: videoEditorCompiler,
      );
      await _verifyActiveRenderCancellation(renderer, project);
      final rendered = await renderer.render(project);
      final output = rendered.outputBytes;
      expect(
        rendered.isSuccess,
        isTrue,
        reason: rendered.engineResult.logs.join('\n'),
      );
      expect(output, isNotNull);
      final outputBytes = output!;
      expect(outputBytes.length, greaterThan(1000));
      final outputSha256 = sha256.convert(outputBytes);

      final metadata = await _probeOutput(ffmpeg, outputBytes);
      final kinds = (metadata['streams']! as List<Object?>)
          .whereType<Map>()
          .map((stream) => stream['codec_type'])
          .toSet();
      expect(kinds, containsAll(<String>['video', 'audio']));
      // The Fleet harness retains this bounded identity without exposing a
      // sandbox path or any media bytes.
      // ignore: avoid_print
      print(
        'II_OS_MOBILE_RENDER_RESULT ${Platform.operatingSystem} '
        '$outputSha256 ${outputBytes.length} video,audio',
      );
      await _verifyActiveRenderDisposal(ffmpeg, renderer, project);

      const saveDialogE2e = bool.fromEnvironment(
        'II_OS_ANDROID_SAVE_DIALOG_E2E',
      );
      const runOwner = String.fromEnvironment('II_OS_E2E_RUN_OWNER');
      if (saveDialogE2e) {
        expect(runOwner, matches(RegExp(r'^[0-9]+-[0-9]+$')));
      }
      final saveName =
          'ii-os-owned-mobile-e2e-'
          '${saveDialogE2e ? runOwner : 'local'}-'
          '${DateTime.now().microsecondsSinceEpoch}';
      final savedPath = await saveLocalEditorMp4(
        bytes: outputBytes,
        name: saveName,
        promptForLocation: saveDialogE2e,
      );
      expect(savedPath, isNotNull);
      if (saveDialogE2e) {
        expect(savedPath, startsWith('content://'));
        final encodedUri = base64Url
            .encode(utf8.encode(savedPath!))
            .replaceAll('=', '');
        // Emit ownership before read-back so the Fleet harness can remove the
        // exact run-owned file even if ContentResolver rejects the grant.
        // ignore: avoid_print
        print(
          'II_OS_ANDROID_SAVE_RESULT $encodedUri $outputSha256 '
          '${outputBytes.length} $saveName.mp4',
        );
        final readback = await readLocalDocumentIdentity(
          savedPath,
          maxBytes: outputBytes.length,
        );
        expect(readback.sha256, outputSha256.toString());
        expect(readback.sizeBytes, outputBytes.length);
        expect(readback.signatureHex, '66747970');
        // The Fleet harness consumes both bounded markers, independently
        // verifies the exact Downloads file, and removes only the owned file.
        // ignore: avoid_print
        print(
          'II_OS_ANDROID_URI_READBACK $encodedUri ${readback.sha256} '
          '${readback.sizeBytes} ${readback.signatureHex}',
        );
        return;
      }
      final saved = File(savedPath!);
      try {
        expect(await saved.readAsBytes(), orderedEquals(outputBytes));
        if (Platform.isIOS) {
          // ignore: avoid_print
          print(
            'II_OS_IOS_SAVE_RESULT $outputSha256 '
            '${outputBytes.length} sandbox-readback',
          );
        }
      } finally {
        if (await saved.exists()) await saved.delete();
      }
      expect(await saved.exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _verifyActiveRenderDisposal(
  UniversalFfmpeg ffmpeg,
  EditorRenderer renderer,
  EditorProject project,
) async {
  final cancellation = EditorRenderCancellationToken();
  final backendStarted = Completer<void>();
  final operation = renderer.render(
    project,
    cancellation: cancellation,
    onStage: (stage) {
      if (stage == EditorRenderStage.renderingMedia &&
          !backendStarted.isCompleted) {
        backendStarted.complete();
      }
    },
  );
  await backendStarted.future.timeout(const Duration(seconds: 30));
  await Future<void>.delayed(const Duration(milliseconds: 1));
  await disposeEditorEngineAfterActiveRender(
    engine: ffmpeg,
    cancellation: cancellation,
    activeRender: operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    ),
  ).timeout(const Duration(seconds: 30));
  await expectLater(
    operation.timeout(const Duration(seconds: 30)),
    throwsA(isA<EditorRenderCancelledException>()),
  );
}

Future<void> _verifyActiveRenderCancellation(
  EditorRenderer renderer,
  EditorProject project,
) async {
  final cancellation = EditorRenderCancellationToken();
  final backendStarted = Completer<void>();
  final operation = renderer.render(
    project,
    cancellation: cancellation,
    onStage: (stage) {
      if (stage == EditorRenderStage.renderingMedia &&
          !backendStarted.isCompleted) {
        backendStarted.complete();
      }
    },
  );
  await backendStarted.future.timeout(const Duration(seconds: 30));
  await Future<void>.delayed(const Duration(milliseconds: 1));
  cancellation.cancel();
  await expectLater(
    operation.timeout(const Duration(seconds: 30)),
    throwsA(isA<EditorRenderCancelledException>()),
  );
}

Future<Map<String, Object?>> _probeOutput(
  UniversalFfmpeg ffmpeg,
  Uint8List output,
) async {
  const outputName = 'ii-os-mobile-output-probe.json';
  final result = await ffmpeg.execute(
    FfmpegJob(
      id: 'ii-os-mobile-output-probe',
      operation: FfmpegOperation.ffprobe,
      arguments: const [
        '-v',
        'error',
        '-show_entries',
        'format=duration:stream=codec_type',
        '-of',
        'json',
        '-f',
        'mov',
        '-i',
        'edited.mp4',
        '-o',
        outputName,
      ],
      inputs: [FfmpegBytesInput('edited.mp4', output)],
      outputs: const [FfmpegOutput(outputName)],
      timeout: const Duration(minutes: 2),
    ),
  );
  final bytes = result.outputBytes[outputName];
  if (!result.isSuccess || bytes == null) {
    // The FFmpeg banner occupies the leading lines; the cause is at the tail.
    final logs = result.logs;
    final tail = logs.length <= 10 ? logs : logs.sublist(logs.length - 10);
    throw StateError(
      'Mobile output probe failed (${result.exitCode}): ${tail.join(' | ')}',
    );
  }
  return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  testWidgets('real Flutter caption rasterizer emits a bounded PNG', (
    tester,
  ) async {
    final caption = testProject().lanes.last.clips.single as EditorCaptionClip;
    final bytes = await tester.runAsync(
      () => const FlutterCaptionRasterizer().rasterize(
        EditorCaptionRasterRequest(
          clip: caption,
          canvasWidth: 640,
          canvasHeight: 360,
          limits: const EditorLimits(),
        ),
        cancellation: EditorRenderCancellationToken(),
      ),
    );

    expect(bytes, isNotNull);
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(bytes.length, lessThan(const EditorLimits().maxCaptionRasterBytes));
  });

  testWidgets('compiler preserves lane order and excludes muted audio', (
    tester,
  ) async {
    final composition = await tester.runAsync(
      () => const EditorCompositionCompiler().compile(
        testProject(mutedAudio: true),
      ),
    );

    expect(composition, isNotNull);
    final compiled = composition!;
    expect(compiled.layers, hasLength(2));
    expect(compiled.layers[0], isA<MediaVideoLayer>());
    expect(compiled.layers[1], isA<MediaImageLayer>());
    final caption = compiled.layers[1] as MediaImageLayer;
    expect(caption.id, 'caption-clip');
    expect(caption.timelineStart, MediaTime.seconds(2));
    expect(caption.sourceRange.duration, MediaTime.seconds(3));
    final bytes = await caption.source.openRead().fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    expect(bytes, hasLength(caption.source.byteLength));
    expect(bytes.take(4), [137, 80, 78, 71]);
    expect(compiled.job.inputs, hasLength(2));
    expect(compiled.job.outputs.single.name, compiled.outputName);
    expect(compiled.job.arguments, isNot(contains('Client-side editing')));
    expect(
      () => const FfmpegSafetyPolicy().validate(compiled.job),
      returnsNormally,
    );
  });

  testWidgets('compiler excludes hidden caption lanes', (tester) async {
    final composition = await tester.runAsync(
      () => const EditorCompositionCompiler().compile(
        testProject(hiddenCaptions: true),
      ),
    );

    expect(composition, isNotNull);
    expect(composition!.layers.whereType<MediaImageLayer>(), isEmpty);
    expect(composition.layers.whereType<MediaVideoLayer>(), hasLength(1));
    expect(composition.layers.whereType<MediaAudioLayer>(), hasLength(1));
  });

  test(
    'compiler loops still-image visual sources without transcoding',
    () async {
      final plan = await const EditorCompositionCompiler().compile(
        testProject(
          videoSource: testSource('transparent-still', 'png'),
          hiddenCaptions: true,
        ),
      );

      expect(plan.layers.whereType<MediaVideoLayer>(), hasLength(1));
      expect(
        plan.job.arguments,
        containsAllInOrder(['-f', 'image2', '-loop', '1', '-i', 'input-0.png']),
      );
      expect(
        () => const FfmpegSafetyPolicy().validate(plan.job),
        returnsNormally,
      );
    },
  );

  test('compiler places a still-image overlay above existing lanes', () async {
    final project = addEditorImageOverlay(
      project: testProject(hiddenCaptions: true),
      laneId: 'brand-lane',
      clipId: 'brand-image',
      source: testSource('brand-image-source', 'png'),
      timelineStart: MediaTime.seconds(1),
      duration: MediaTime.seconds(3),
      destination: const MediaRect(x: 0.7, y: 0.05, width: 0.25, height: 0.25),
    );

    final plan = await const EditorCompositionCompiler().compile(project);
    final visualLayers = plan.layers
        .where((layer) => layer is! MediaAudioLayer)
        .toList();
    expect(visualLayers.map((layer) => layer.id), [
      'video-clip',
      'brand-image',
    ]);
    expect((visualLayers.last as MediaVideoLayer).destination.width, 0.25);
    expect(
      plan.job.arguments,
      containsAllInOrder(['-f', 'image2', '-loop', '1']),
    );
  });

  test('caption raster request rejects excessive output pixels', () async {
    final caption = testProject().lanes.last.clips.single as EditorCaptionClip;
    await expectLater(
      const FlutterCaptionRasterizer().rasterize(
        EditorCaptionRasterRequest(
          clip: caption,
          canvasWidth: 640,
          canvasHeight: 360,
          limits: const EditorLimits(maxCaptionPixels: 2),
        ),
        cancellation: EditorRenderCancellationToken(),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('compiler rejects non-PNG callback output', () async {
    final compiler = EditorCompositionCompiler(
      captionRasterizer: CallbackCaptionRasterizer(
        (request, cancellation) async => Uint8List.fromList([1, 2, 3, 4]),
      ),
    );

    await expectLater(
      compiler.compile(testProject()),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test(
    'compiler enforces callback raster pixel bounds before invocation',
    () async {
      var invoked = false;
      final compiler = EditorCompositionCompiler(
        limits: const EditorLimits(maxCaptionPixels: 8),
        captionRasterizer: CallbackCaptionRasterizer((
          request,
          cancellation,
        ) async {
          invoked = true;
          return Uint8List(0);
        }),
      );

      await expectLater(
        compiler.compile(testProject()),
        throwsA(isA<EditorValidationException>()),
      );
      expect(invoked, isFalse);
    },
  );

  test(
    'compiler rejects oversized callback bytes before PNG parsing',
    () async {
      final compiler = EditorCompositionCompiler(
        limits: const EditorLimits(maxCaptionRasterBytes: 64),
        captionRasterizer: CallbackCaptionRasterizer(
          (request, cancellation) async => Uint8List(65),
        ),
      );

      await expectLater(
        compiler.compile(testProject()),
        throwsA(isA<EditorValidationException>()),
      );
    },
  );

  test('compiler rejects a PNG whose IHDR exceeds requested pixels', () async {
    final compiler = EditorCompositionCompiler(
      captionRasterizer: CallbackCaptionRasterizer((
        request,
        cancellation,
      ) async {
        final bytes = Uint8List(33);
        bytes.setAll(0, const [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        header.setUint32(8, 13, Endian.big);
        bytes.setAll(12, const [73, 72, 68, 82]);
        header.setUint32(16, request.pixelWidth + 1, Endian.big);
        header.setUint32(20, request.pixelHeight, Endian.big);
        return bytes;
      }),
    );

    await expectLater(
      compiler.compile(testProject()),
      throwsA(isA<EditorValidationException>()),
    );
  });

  testWidgets('compiler rejects malformed PNG chunk streams', (tester) async {
    final caption = testProject().lanes.last.clips.single as EditorCaptionClip;
    final valid = await tester.runAsync(
      () => const FlutterCaptionRasterizer().rasterize(
        EditorCaptionRasterRequest(
          clip: caption,
          canvasWidth: 640,
          canvasHeight: 360,
          limits: const EditorLimits(),
        ),
        cancellation: EditorRenderCancellationToken(),
      ),
    );
    final invalid = <Uint8List>[
      Uint8List.fromList(valid!.sublist(0, valid.length - 12)),
      Uint8List.fromList([...valid, 0]),
      Uint8List.fromList(valid)..[valid.length - 1] ^= 1,
      _corruptFirstIdat(valid),
    ];

    final rejected = await tester.runAsync(() async {
      for (final bytes in invalid) {
        final compiler = EditorCompositionCompiler(
          captionRasterizer: CallbackCaptionRasterizer(
            (request, cancellation) async => bytes,
          ),
        );
        try {
          await compiler.compile(testProject());
          return false;
        } on EditorValidationException {
          // Expected: malformed callback output never reaches FFmpeg.
        }
      }
      return true;
    });
    expect(rejected, isTrue);
  });

  test('cancelled preparation returns no execution plan', () async {
    final cancellation = EditorRenderCancellationToken()..cancel();

    await expectLater(
      const EditorCompositionCompiler().compile(
        testProject(hiddenCaptions: true),
        cancellation: cancellation,
      ),
      throwsA(isA<EditorRenderCancelledException>()),
    );
  });

  test(
    'caption preparation cancels without waiting for stalled work',
    () async {
      final cancellation = EditorRenderCancellationToken();
      final compiler = EditorCompositionCompiler(
        captionRasterizer: CallbackCaptionRasterizer((_, token) async {
          await token.whenCancelled;
          token.throwIfCancelled();
          throw StateError('unreachable');
        }),
      );
      final compiling = compiler.compile(
        testProject(),
        cancellation: cancellation,
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();

      await expectLater(
        compiling.timeout(const Duration(seconds: 1)),
        throwsA(isA<EditorRenderCancelledException>()),
      );
    },
  );

  test(
    'caption preparation times out and signals cooperative cancellation',
    () async {
      final observed = Completer<void>();
      final compiler = EditorCompositionCompiler(
        limits: const EditorLimits(
          captionRasterTimeout: Duration(milliseconds: 20),
        ),
        captionRasterizer: CallbackCaptionRasterizer((_, token) async {
          await token.whenCancelled;
          observed.complete();
          return Uint8List(0);
        }),
      );

      await expectLater(
        compiler.compile(testProject()),
        throwsA(isA<EditorValidationException>()),
      );
      await observed.future.timeout(const Duration(seconds: 1));
    },
  );

  test('compiler enforces aggregate media input bytes before render', () async {
    final compiler = EditorCompositionCompiler(
      captionRasterizer: CallbackCaptionRasterizer(
        (request, cancellation) async =>
            Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
    );
    await expectLater(
      compiler.compile(
        testProject(),
        mediaLimits: const MediaLimits(maxInputBytes: 8),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test(
    'compiler rejects one source ID bound to distinct byte streams',
    () async {
      final video = testSource('shared-source', 'mp4');
      final audio = MediaSource(
        id: 'shared-source',
        byteLength: 4,
        fileExtension: 'm4a',
        openRead: () => Stream<List<int>>.value(const [5, 6, 7, 8]),
      );

      await expectLater(
        const EditorCompositionCompiler().compile(
          testProject(
            videoSource: video,
            audioSource: audio,
            hiddenCaptions: true,
          ),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    },
  );

  test(
    'compiler rejects a source stream shorter than its declaration',
    () async {
      final source = MediaSource(
        id: 'short-source',
        byteLength: 4,
        fileExtension: 'mp4',
        openRead: () => Stream<List<int>>.value(const [1, 2, 3]),
      );

      await expectLater(
        const EditorCompositionCompiler().compile(
          testProject(
            videoSource: source,
            mutedAudio: true,
            hiddenCaptions: true,
          ),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    },
  );

  test('non-cooperative source cancellation remains bounded', () async {
    final releaseCancellation = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () => releaseCancellation.future,
    );
    final source = MediaSource(
      id: 'stalled-source',
      byteLength: 1,
      fileExtension: 'mp4',
      openRead: () => controller.stream,
    );
    final cancellation = EditorRenderCancellationToken();
    final compiling = const EditorCompositionCompiler().compile(
      testProject(videoSource: source, mutedAudio: true, hiddenCaptions: true),
      mediaLimits: const MediaLimits(
        sourceCancellationTimeout: Duration(milliseconds: 20),
      ),
      cancellation: cancellation,
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();

    await expectLater(
      compiling.timeout(const Duration(seconds: 1)),
      throwsA(isA<EditorRenderCancelledException>()),
    );
    releaseCancellation.complete();
    await controller.close();
  });

  test(
    'maximum supported layer count fits Universal argument bounds',
    () async {
      final source = testSource('shared-max-source', 'mp4');
      final duration = MediaTime.seconds(1);
      final project = EditorProject(
        id: 'maximum-layer-project',
        width: 640,
        height: 360,
        framesPerSecond: 30,
        duration: duration,
        lanes: [
          for (
            var index = 0;
            index < const MediaLimits().maxLayerCount;
            index++
          )
            EditorLane(
              id: 'maximum-lane-$index',
              label: 'Maximum lane $index',
              kind: EditorLaneKind.video,
              clips: [
                EditorVideoClip(
                  id: 'maximum-clip-$index',
                  timelineStart: MediaTime.zero,
                  duration: duration,
                  source: source,
                  sourceRange: MediaRange(
                    start: MediaTime.zero,
                    duration: duration,
                  ),
                  destination: const MediaRect.full(),
                  fit: MediaFit.cover,
                  opacity: 0.1234,
                ),
              ],
            ),
        ],
      );

      final plan = await const EditorCompositionCompiler().compile(project);

      expect(plan.layers, hasLength(const MediaLimits().maxLayerCount));
      expect(
        () => const FfmpegSafetyPolicy().validate(plan.job),
        returnsNormally,
      );
      expect(
        plan.job.arguments
            .map((value) => value.codeUnits.length)
            .reduce((maximum, value) => value > maximum ? value : maximum),
        lessThanOrEqualTo(16 * 1024),
      );
    },
  );
}

Uint8List _corruptFirstIdat(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final length = data.getUint32(offset, Endian.big);
    final payloadStart = offset + 8;
    final payloadEnd = payloadStart + length;
    if (payloadEnd + 4 > bytes.length) break;
    if (bytes[offset + 4] == 73 &&
        bytes[offset + 5] == 68 &&
        bytes[offset + 6] == 65 &&
        bytes[offset + 7] == 84 &&
        length > 0) {
      bytes[payloadStart] = 0;
      data.setUint32(
        payloadEnd,
        _testPngCrc(bytes, offset + 4, payloadEnd),
        Endian.big,
      );
      return bytes;
    }
    offset = payloadEnd + 4;
  }
  throw StateError('Flutter PNG did not contain nonempty IDAT data.');
}

int _testPngCrc(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index++) {
    crc ^= bytes[index];
    for (var bit = 0; bit < 8; bit++) {
      crc = crc.isOdd ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

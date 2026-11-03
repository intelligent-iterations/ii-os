@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_os/services/video_last_frame_capture_io.dart';
import 'package:ii_os/services/video_last_frame_capture_limits.dart';

Uint8List _png({int extra = 0}) => Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ...List.filled(extra, 0),
]);

FfmpegResult _result({
  int exitCode = 0,
  Map<String, Uint8List>? outputBytes,
  bool timedOut = false,
  bool cancelled = false,
}) => FfmpegResult(
  jobId: 'video-last-frame',
  backend: 'test',
  exitCode: exitCode,
  elapsed: Duration.zero,
  logs: const [],
  outputBytes: outputBytes ?? {'last-frame.png': _png()},
  timedOut: timedOut,
  cancelled: cancelled,
);

void main() {
  group('videoLastFrameFfmpegArguments', () {
    test('keeps every token a distinct argument', () {
      // The runtime passes these as an argv list, never through a shell. A
      // name carrying a space or a semicolon must stay one argument.
      final arguments = videoLastFrameFfmpegArguments(
        inputName: 'source video;still-one-argument.mp4',
        outputName: 'last frame.png',
      );

      expect(
        arguments[arguments.indexOf('-i') + 1],
        'source video;still-one-argument.mp4',
      );
      expect(arguments.last, 'last frame.png');
    });

    test('seeks from the end rather than decoding the whole source', () {
      final arguments = videoLastFrameFfmpegArguments(
        inputName: 'in',
        outputName: 'out.png',
      );

      // -sseof is what keeps this bounded on a long video; losing it would
      // still produce a correct frame, just after decoding everything.
      expect(arguments, containsAllInOrder(const ['-sseof', '-0.05', '-i']));
      expect(arguments, containsAllInOrder(const ['-frames:v', '1']));
      expect(arguments, containsAllInOrder(const ['-c:v', 'png']));
    });

    test('pins the first video stream', () {
      // Without this a source carrying cover art can hand back the album
      // thumbnail instead of a frame of the video.
      expect(
        videoLastFrameFfmpegArguments(inputName: 'in', outputName: 'out.png'),
        containsAllInOrder(const ['-map', '0:v:0']),
      );
    });
  });

  group('hasPngSignature', () {
    test('accepts only the complete signature', () {
      final png = _png(extra: 1);
      expect(hasPngSignature(png), isTrue);
      expect(hasPngSignature(Uint8List.fromList(png.sublist(0, 7))), isFalse);

      png[3] = 0;
      expect(hasPngSignature(png), isFalse);
    });

    test('rejects empty bytes', () {
      expect(hasPngSignature(Uint8List(0)), isFalse);
    });
  });

  group('videoLastFrameJob', () {
    test('carries the source as bytes, never a device path', () {
      // A path input would reach outside the runtime's owned workspace, and
      // the browser backend rejects them outright.
      final job = videoLastFrameJob(_png());

      expect(job.inputs.single, isA<FfmpegBytesInput>());
      expect(job.inputs.single.name, 'source-video');
    });

    test('names the output the arguments actually write', () {
      final job = videoLastFrameJob(_png());

      // The runtime returns bytes keyed by output name. A mismatch between
      // this and the argument list yields a successful run with no frame.
      expect(job.outputs.single.name, job.arguments.last);
    });

    test('bounds the output and the run', () {
      final job = videoLastFrameJob(_png());

      expect(job.outputs.single.maxBytes, maxVideoLastFrameBytes);
      expect(job.timeout, isNotNull);
      expect(job.operation, FfmpegOperation.ffmpeg);
    });

    test('copies the source so a later mutation cannot change the job', () {
      final bytes = _png(extra: 4);
      final job = videoLastFrameJob(bytes);
      bytes[8] = 0xFF;

      expect((job.inputs.single as FfmpegBytesInput).bytes[8], 0);
    });
  });

  group('readCapturedFrame', () {
    test('returns the frame on a successful run', () {
      expect(readCapturedFrame(_result()), _png());
    });

    test('reports a timeout distinctly from a decode failure', () {
      // The operator can retry a timeout; a decode failure means this source
      // will never produce a frame, so the two must not read the same.
      expect(
        () => readCapturedFrame(_result(timedOut: true)),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('timed out')),
        ),
      );
    });

    test('rejects a non-zero exit', () {
      expect(
        () => readCapturedFrame(_result(exitCode: 1)),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a cancelled run even with a zero exit code', () {
      expect(
        () => readCapturedFrame(_result(cancelled: true)),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a success that produced no output', () {
      expect(
        () => readCapturedFrame(_result(outputBytes: {})),
        throwsA(isA<StateError>()),
      );
      expect(
        () => readCapturedFrame(
          _result(outputBytes: {'last-frame.png': Uint8List(0)}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects output that is not a PNG', () {
      // The caller uploads this as image/png. Mislabelling an object in the
      // workspace bucket is worse than failing the extend.
      expect(
        () => readCapturedFrame(
          _result(outputBytes: {'last-frame.png': Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a frame over the shared ceiling', () {
      final oversized = Uint8List(maxVideoLastFrameBytes + 1);
      oversized.setRange(0, 8, _png());

      expect(
        () => readCapturedFrame(_result(outputBytes: {'last-frame.png': oversized})),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

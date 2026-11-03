import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_ffmpeg_universal/src/execution_constraints.dart';

void main() {
  group('managed FFmpeg argument policy', () {
    const policy = FfmpegSafetyPolicy(maxInputBytes: 4);

    test('rejects labeled filter graphs that read files', () {
      for (final filter in [
        "[0:v]sendcmd=filename='/etc/hosts'",
        '[0:v]subtitles@captions=filename="/tmp/captions.srt"',
        '[0:v]drawtext=textfile=/tmp/title.txt',
        "[0:v]lut3d=file='//etc/hosts'",
        r'[0:v]lut3d=file=file\:/etc/hosts',
        r'[0:v]lut3d=file=C:\Windows\system.ini',
      ]) {
        final job = FfmpegJob(
          id: 'labeled-file-filter-job',
          arguments: [
            '-i',
            'input.mp4',
            '-filter_complex',
            filter,
            'output.mp4',
          ],
          inputs: [FfmpegBytesInput('input.mp4', Uint8List(1))],
          outputs: const [FfmpegOutput('output.mp4')],
        );

        expect(
          () => policy.validate(job),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.unsafeArgument,
            ),
          ),
          reason: filter,
        );
      }
    });

    test('rejects file-reading lavfi sources', () {
      final job = FfmpegJob(
        id: 'lavfi-file-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'movie=/etc/passwd',
          '-frames:v',
          '1',
          '-f',
          'image2',
          'output.bmp',
        ],
        outputs: const [FfmpegOutput('output.bmp')],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('accepts an allowlisted generated lavfi source', () {
      final job = FfmpegJob(
        id: 'lavfi-generated-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=c=purple:s=160x90:r=10:d=0.2',
          '-frames:v',
          '1',
          '-f',
          'image2',
          'output.bmp',
        ],
        outputs: const [FfmpegOutput('output.bmp')],
      );

      expect(() => policy.validate(job), returnsNormally);
    });

    test('rejects extension-inferred output muxers', () {
      final job = FfmpegJob(
        id: 'inferred-side-file-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=64x64:d=1',
          'output.m3u8',
        ],
        outputs: const [FfmpegOutput('output.m3u8')],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('rejects side-file muxers', () {
      final job = FfmpegJob(
        id: 'side-file-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=64x64:d=1',
          '-f',
          'hls',
          'output.mp4',
        ],
        outputs: const [FfmpegOutput('output.mp4')],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('rejects binary stdout sinks but allows the null muxer', () {
      final streaming = FfmpegJob(
        id: 'stdout-stream',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=16x16:d=1',
          '-f',
          'rawvideo',
          '-',
        ],
      );
      final discarding = FfmpegJob(
        id: 'null-stream',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=16x16:d=1',
          '-f',
          'null',
          '-',
        ],
      );

      expect(
        () => policy.validate(streaming),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
      expect(() => policy.validate(discarding), returnsNormally);
    });

    test('requires an explicit safe demuxer for declared inputs', () {
      final job = FfmpegJob(
        id: 'autoprobe-job',
        arguments: const ['-i', 'playlist.m3u8', '-f', 'null', '-'],
        inputs: [FfmpegBytesInput('playlist.m3u8', Uint8List(1))],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('engine constraints allow only owned file input protocols', () {
      final job = FfmpegJob(
        id: 'file-protocol-only',
        arguments: const ['-f', 'mov', '-i', 'input.mp4', '-f', 'null', '-'],
        inputs: [FfmpegBytesInput('input.mp4', Uint8List(1))],
      );

      final arguments = constrainManagedExecution(
        job,
        const FfmpegSafetyPolicy(),
      );

      expect(
        arguments,
        containsAllInOrder(const [
          '-f',
          'mov',
          '-protocol_whitelist',
          'file',
          '-i',
          'input.mp4',
        ]),
      );
      expect(arguments, isNot(contains('file,pipe')));
    });

    test('rejects filters that write undeclared side files', () {
      final job = FfmpegJob(
        id: 'filter-side-file-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=64x64:d=1',
          '-filter:v',
          'metadata=mode=print:file=side.txt',
          '-f',
          'null',
          '-',
        ],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('rejects allowlist candidates with positional file options', () {
      for (final values in [
        (
          source: 'color=black:s=64x64:d=1',
          option: '-filter:v',
          filter: 'drawtext=Sans:hello:.ii-disposable-owner',
        ),
        (
          source: 'sine=frequency=440:duration=1',
          option: '-filter:a',
          filter:
              'loudnorm=-24:7:-2:0:0:0:-70:0:true:false:json:'
              '.ii-disposable-owner',
        ),
      ]) {
        final job = FfmpegJob(
          id: 'positional-filter-file-option',
          arguments: [
            '-f',
            'lavfi',
            '-i',
            values.source,
            values.option,
            values.filter,
            '-f',
            'null',
            '-',
          ],
        );

        expect(
          () => policy.validate(job),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.unsafeArgument,
            ),
          ),
          reason: values.filter,
        );
      }
    });

    test('validates every indexed stream filter through the safe profile', () {
      for (final option in ['-filter:v:0', '-filter:a:12']) {
        final job = FfmpegJob(
          id: 'indexed-filter-side-file-job',
          arguments: [
            '-f',
            'lavfi',
            '-i',
            option.startsWith('-filter:v')
                ? 'color=black:s=64x64:d=1'
                : 'sine=frequency=440:duration=1',
            option,
            'metadata=mode=print:file=.ii-disposable-owner',
            '-f',
            'null',
            '-',
          ],
        );

        expect(
          () => policy.validate(job),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.unsafeArgument,
            ),
          ),
          reason: option,
        );
      }
    });

    test('rejects unsupported and malformed option specifiers', () {
      for (final option in ['-f:0', '-i:0', '-filter:v:x', '-filter:v:1000']) {
        final job = FfmpegJob(
          id: 'invalid-option-specifier-job',
          arguments: [option, 'mov', '-f', 'null', '-'],
        );

        expect(
          () => policy.validate(job),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.unsafeArgument,
            ),
          ),
          reason: option,
        );
      }
    });

    test('accepts an allowlisted multi-lane filter graph', () {
      final job = FfmpegJob(
        id: 'safe-filter-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=64x64:d=1',
          '-filter_complex',
          '[0:v]trim=start=0:end=1,setpts=PTS-STARTPTS[v]',
          '-map',
          '[v]',
          '-f',
          'null',
          '-',
        ],
      );

      expect(() => policy.validate(job), returnsNormally);
    });

    test('accepts bounded generated color and silence filter sources', () {
      final job = FfmpegJob(
        id: 'safe-generated-filter-sources',
        arguments: const [
          '-filter_complex',
          'color=c=black:s=64x64:r=10:d=1[v];'
              'anullsrc=channel_layout=stereo:sample_rate=48000,'
              'atrim=duration=1[a]',
          '-map',
          '[v]',
          '-map',
          '[a]',
          '-f',
          'null',
          '-',
        ],
      );

      expect(() => policy.validate(job), returnsNormally);
    });

    test('requires declared FFprobe output', () {
      final job = FfmpegJob(
        id: 'probe-job',
        operation: FfmpegOperation.ffprobe,
        arguments: const ['-i', 'input.mp4'],
        inputs: [FfmpegBytesInput('input.mp4', Uint8List(1))],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.invalidJob,
          ),
        ),
      );
    });

    test('rejects unbounded FFprobe packet enumeration', () {
      final job = FfmpegJob(
        id: 'packet-probe-job',
        operation: FfmpegOperation.ffprobe,
        arguments: const [
          '-show_entries',
          'packet=pts',
          '-of',
          'json',
          '-f',
          'mov',
          '-i',
          'input.mp4',
          '-o',
          'probe.json',
        ],
        inputs: [FfmpegBytesInput('input.mp4', Uint8List(1))],
        outputs: const [FfmpegOutput('probe.json')],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });
  });
}

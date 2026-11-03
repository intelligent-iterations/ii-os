import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_ffmpeg_universal/src/execution_constraints.dart';

void main() {
  group('FfmpegSafetyPolicy', () {
    const policy = FfmpegSafetyPolicy(maxInputBytes: 4);

    test('accepts portable named byte resources', () {
      final job = FfmpegJob(
        id: 'safe-job',
        arguments: const [
          '-f',
          'mov',
          '-i',
          'input.mp4',
          '-f',
          'mp4',
          'output.mp4',
        ],
        inputs: [FfmpegBytesInput('input.mp4', Uint8List(4))],
        outputs: const [FfmpegOutput('output.mp4')],
      );

      expect(() => policy.validate(job), returnsNormally);
    });

    test('rejects path traversal resource names', () {
      final job = FfmpegJob(
        id: 'unsafe-job',
        arguments: const ['-i', '../input.mp4', 'output.mp4'],
        inputs: [FfmpegBytesInput('../input.mp4', Uint8List(1))],
        outputs: const [FfmpegOutput('output.mp4')],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.invalidResourceName,
          ),
        ),
      );
    });

    test('rejects NUL bytes in arguments', () {
      final job = FfmpegJob(
        id: 'nul-argument-job',
        arguments: const ['-i', 'input.mp4\u0000suffix', 'output.mp4'],
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
      );
    });

    test('rejects Windows device names and aliases', () {
      for (final name in ['CON', 'nul.mp4', 'COM1.bin', 'trailing.']) {
        final job = FfmpegJob(
          id: 'windows-name-job',
          arguments: ['-i', name, 'output.mp4'],
          inputs: [FfmpegBytesInput(name, Uint8List(1))],
          outputs: const [FfmpegOutput('output.mp4')],
        );
        expect(
          () => policy.validate(job),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.invalidResourceName,
            ),
          ),
          reason: name,
        );
      }
    });

    test('rejects case-insensitive resource collisions', () {
      final job = FfmpegJob(
        id: 'case-collision-job',
        arguments: const ['-i', 'clip.mp4', 'CLIP.MP4'],
        inputs: [FfmpegBytesInput('clip.mp4', Uint8List(1))],
        outputs: const [FfmpegOutput('CLIP.MP4')],
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

    test('rejects native device namespaces and alternate data streams', () {
      for (final destination in [
        r'\\.\NUL',
        r'\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\file.mp4',
        r'C:\safe\render.mp4:secret',
        '/tmp/CON/output.mp4',
      ]) {
        final job = FfmpegJob(
          id: 'unsafe-native-destination',
          arguments: const [
            '-f',
            'lavfi',
            '-i',
            'color=black:s=16x16:d=0.1',
            '-f',
            'mp4',
            'output.mp4',
          ],
          outputs: [FfmpegOutput('output.mp4', destinationPath: destination)],
        );

        expect(
          () => const FfmpegSafetyPolicy().validate(job),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.invalidJob,
            ),
          ),
          reason: destination,
        );
      }
    });

    test('rejects network protocols by default', () {
      final job = FfmpegJob(
        id: 'network-job',
        arguments: const ['-i', 'https://example.com/video.mp4', 'output.mp4'],
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

    test('rejects oversized byte inputs', () {
      final job = FfmpegJob(
        id: 'large-job',
        arguments: const ['-i', 'input.mp4', 'output.mp4'],
        inputs: [FfmpegBytesInput('input.mp4', Uint8List(5))],
        outputs: const [FfmpegOutput('output.mp4')],
      );

      expect(
        () => policy.validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.inputTooLarge,
          ),
        ),
      );
    });

    test(
      'caps argument and declared-resource cardinality before execution',
      () {
        final jobs = [
          FfmpegJob(
            id: 'too-many-arguments',
            arguments: List.filled(
              FfmpegSafetyPolicy.maxManagedArguments + 1,
              '-n',
            ),
          ),
          FfmpegJob(
            id: 'too-many-inputs',
            arguments: const ['-f', 'null', '-'],
            inputs: List.generate(
              FfmpegSafetyPolicy.maxManagedInputs + 1,
              (index) => FfmpegBytesInput('input$index.bin', Uint8List(0)),
            ),
          ),
          FfmpegJob(
            id: 'too-many-outputs',
            arguments: const ['-f', 'null', '-'],
            outputs: List.generate(
              FfmpegSafetyPolicy.maxManagedOutputs + 1,
              (index) => FfmpegOutput('output$index.bin'),
            ),
          ),
        ];

        for (final job in jobs) {
          expect(
            () => const FfmpegSafetyPolicy().validate(job),
            throwsA(
              isA<FfmpegException>().having(
                (error) => error.code,
                'code',
                FfmpegErrorCode.invalidJob,
              ),
            ),
            reason: job.id,
          );
        }
      },
    );

    test('caps arguments by UTF-8 bytes rather than Dart code units', () {
      final multibyte = List.filled(6000, '漢').join();
      expect(
        multibyte.length,
        lessThan(FfmpegSafetyPolicy.maxManagedArgumentBytes),
      );
      final job = FfmpegJob(
        id: 'multibyte-argument',
        arguments: ['-metadata', multibyte, '-f', 'null', '-'],
      );

      expect(
        () => const FfmpegSafetyPolicy().validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('caps the aggregate portable argument budget', () {
      final value = List.filled(13000, 'x').join();
      final job = FfmpegJob(
        id: 'aggregate-argument-budget',
        arguments: ['-metadata', value, '-metadata', value, '-f', 'null', '-'],
      );

      expect(
        () => const FfmpegSafetyPolicy().validate(job),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
    });

    test('rejects undeclared positional paths', () {
      final job = FfmpegJob(
        id: 'filesystem-job',
        arguments: const ['-i', '/etc/passwd', 'output.mp4'],
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

    test('rejects declared resources reused as option values', () {
      final job = FfmpegJob(
        id: 'resource-role-job',
        arguments: const [
          '-i',
          'input.mp4',
          '-metadata',
          'output.mp4',
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
      );
    });

    test('rejects file-reading filters', () {
      final job = FfmpegJob(
        id: 'filter-file-job',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=64x64:d=1',
          '-filter:v',
          'subtitles=/private/subtitle.srt',
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
  });

  test('byte inputs snapshot caller-owned memory', () {
    final callerBytes = Uint8List.fromList([1, 2, 3]);
    final input = FfmpegBytesInput('input.bin', callerBytes);
    callerBytes[0] = 99;

    expect(input.bytes, [1, 2, 3]);
    expect(() => input.bytes[0] = 7, throwsUnsupportedError);
  });

  test('managed jobs allow only one externally published destination', () {
    final job = FfmpegJob(
      id: 'multiple-destinations',
      arguments: const [
        '-f',
        'lavfi',
        '-i',
        'color=black:s=16x16:d=0.1',
        '-f',
        'image2',
        'first.bmp',
        '-f',
        'image2',
        'second.bmp',
      ],
      outputs: const [
        FfmpegOutput('first.bmp', destinationPath: '/tmp/first.bmp'),
        FfmpegOutput('second.bmp', destinationPath: '/tmp/second.bmp'),
      ],
    );

    expect(
      () => const FfmpegSafetyPolicy().validate(job),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.invalidJob,
        ),
      ),
    );
  });

  test('backend caps and aggregate shares use one output limit', () {
    const first = FfmpegOutput('first.bin');
    const second = FfmpegOutput('second.bin');
    final job = FfmpegJob(
      id: 'effective-output-limit',
      arguments: const ['-f', 'rawvideo', 'first.bin'],
      outputs: const [first, second],
    );
    const safety = FfmpegSafetyPolicy(
      maxInputBytes: 100,
      maxTotalInputBytes: 100,
      maxOutputBytes: 1000,
      maxTotalOutputBytes: 1000,
      maxWorkspaceBytes: 1000,
      maxEngineAllocationBytes: 100,
    );

    expect(executionOutputLimit(job, first, safety, hardOutputBytes: 600), 500);
    expect(
      constrainManagedExecution(
        job,
        safety,
        hardOutputBytes: 600,
        workspaceBytesAlreadyUsed: 0,
        outputOvershootReserveBytes: 100,
        maxEngineAllocationBytes: 100,
      ),
      [
        '-filter_threads',
        '1',
        '-filter_complex_threads',
        '1',
        '-max_alloc',
        '100',
        '-f',
        'rawvideo',
        '-threads',
        '1',
        '-fs',
        '400',
        'first.bin',
      ],
    );

    expect(
      () => constrainManagedExecution(
        job,
        safety,
        workspaceBytesAlreadyUsed: 850,
        outputOvershootReserveBytes: 100,
      ),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.outputTooLarge,
        ),
      ),
    );
  });
}

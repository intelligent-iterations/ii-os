import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:path/path.dart' as p;

part 'live_process_test_support.dart';
part 'live_process_security_tests.dart';

void _liveTest(String description, FutureOr<void> Function() body) {
  test(description, body, timeout: const Timeout(Duration(minutes: 3)));
}

void main() {
  late FfmpegConfiguration configuration;
  late Directory suiteState;
  const suiteOwner = 'ii-ffmpeg-universal-live-suite-v1';

  setUpAll(() async {
    suiteState = await Directory.systemTemp.createTemp(
      'ii_ffmpeg_universal_live_suite_',
    );
    await File(
      p.join(suiteState.path, '.ii-disposable-owner'),
    ).writeAsString(suiteOwner, flush: true);
    final desktopBundle = await _resolveTestDesktopBundle();
    configuration = FfmpegConfiguration(
      safety: const FfmpegSafetyPolicy(defaultTimeout: Duration(minutes: 2)),
      nativeWorkspaceRoot: p.join(suiteState.path, 'native-workspaces'),
      desktopBundle: desktopBundle,
    );
    _liveWorkspaceRoot = configuration.nativeWorkspaceRoot!;
  });

  tearDownAll(() async {
    final marker = File(p.join(suiteState.path, '.ii-disposable-owner'));
    if (await marker.exists() && await marker.readAsString() == suiteOwner) {
      await suiteState.delete(recursive: true);
    }
  });

  _liveTest(
    'desktop refuses ambient PATH and incorrect binary attestations',
    () async {
      final withoutBundle = UniversalFfmpeg();
      addTearDown(withoutBundle.dispose);
      await expectLater(
        withoutBundle.initialize(),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.engineUnavailable,
          ),
        ),
      );

      final bundle = configuration.desktopBundle!;
      final incorrectDigest = UniversalFfmpeg(
        configuration: FfmpegConfiguration(
          nativeWorkspaceRoot: configuration.nativeWorkspaceRoot,
          desktopBundle: FfmpegDesktopBundle(
            ffmpegPath: bundle.ffmpegPath,
            ffmpegSha256:
                '0000000000000000000000000000000000000000000000000000000000000000',
            ffprobePath: bundle.ffprobePath,
            ffprobeSha256: bundle.ffprobeSha256,
          ),
        ),
      );
      addTearDown(incorrectDigest.dispose);
      await expectLater(
        incorrectDigest.initialize(),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.engineUnavailable,
          ),
        ),
      );

      if (bundle.dynamicLibraries.isNotEmpty) {
        final firstDependency = bundle.dynamicLibraries.first;
        final incorrectlyAttestedLibraries = UniversalFfmpeg(
          configuration: FfmpegConfiguration(
            nativeWorkspaceRoot: configuration.nativeWorkspaceRoot,
            desktopBundle: FfmpegDesktopBundle(
              ffmpegPath: bundle.ffmpegPath,
              ffmpegSha256: bundle.ffmpegSha256,
              ffprobePath: bundle.ffprobePath,
              ffprobeSha256: bundle.ffprobeSha256,
              dynamicLibraries: [
                FfmpegDesktopDependency(
                  name: firstDependency.name,
                  path: firstDependency.path,
                  sha256:
                      '0000000000000000000000000000000000000000000000000000000000000000',
                ),
                ...bundle.dynamicLibraries.skip(1),
              ],
            ),
          ),
        );
        addTearDown(incorrectlyAttestedLibraries.dispose);
        await expectLater(
          incorrectlyAttestedLibraries.initialize(),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.engineUnavailable,
            ),
          ),
        );
      }

      if (Platform.isMacOS && bundle.dynamicLibraries.isNotEmpty) {
        final fixtureDirectory = await _ownedTestDirectory('escaping_rpath');
        final fixture = await File(
          bundle.ffmpegPath,
        ).copy(p.join(fixtureDirectory.path, 'ffmpeg'));
        final directDependencies = await _machODependencies(bundle.ffmpegPath);
        expect(directDependencies, isNotEmpty);
        final escaped = directDependencies.entries.first;
        final mutation = await Process.run('/usr/bin/install_name_tool', [
          '-change',
          escaped.value,
          '@loader_path/../../outside/${escaped.key}',
          fixture.path,
        ]);
        expect(mutation.exitCode, 0, reason: '${mutation.stderr}');
        final escapingRpath = UniversalFfmpeg(
          configuration: FfmpegConfiguration(
            nativeWorkspaceRoot: configuration.nativeWorkspaceRoot,
            desktopBundle: FfmpegDesktopBundle(
              ffmpegPath: fixture.path,
              ffmpegSha256: await _sha256File(fixture.path),
              ffprobePath: bundle.ffprobePath,
              ffprobeSha256: bundle.ffprobeSha256,
              dynamicLibraries: bundle.dynamicLibraries,
            ),
          ),
        );
        addTearDown(escapingRpath.dispose);
        await expectLater(
          escapingRpath.initialize(),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.engineUnavailable,
            ),
          ),
        );
      }
    },
  );

  _liveTest(
    'real FFmpeg renders media bytes and real FFprobe reads them',
    () async {
      final before = _workspaces('live_render');
      final ffmpeg = UniversalFfmpeg(configuration: configuration);
      addTearDown(ffmpeg.dispose);
      expect(ffmpeg.capabilities.enforcesWorkspaceLimitBeforeWrite, isFalse);
      expect(ffmpeg.capabilities.enforcesEngineMemoryLimit, isFalse);
      expect(ffmpeg.capabilities.acceptsUntrustedMedia, isFalse);
      await ffmpeg.initialize();

      final render = await ffmpeg.execute(
        FfmpegJob(
          id: 'live_render',
          arguments: const [
            '-f',
            'lavfi',
            '-i',
            'color=c=blue:s=160x90:r=25:d=0.4',
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:sample_rate=44100:duration=0.4',
            '-shortest',
            '-c:v',
            'mpeg4',
            '-q:v',
            '5',
            '-c:a',
            'aac',
            '-f',
            'mp4',
            'output.mp4',
          ],
          outputs: const [FfmpegOutput('output.mp4')],
          expectedDuration: const Duration(milliseconds: 400),
        ),
      );

      expect(render.isSuccess, isTrue, reason: _resultDiagnostics(render));
      final video = render.outputBytes['output.mp4'];
      expect(video, isNotNull);
      expect(video!.length, greaterThan(1000));

      final probe = await ffmpeg.execute(
        FfmpegJob(
          id: 'live_probe',
          operation: FfmpegOperation.ffprobe,
          arguments: const [
            '-v',
            'error',
            '-show_entries',
            'format=duration',
            '-of',
            'json',
            '-f',
            'mov',
            '-i',
            'input.mp4',
            '-o',
            'probe.json',
          ],
          inputs: [FfmpegBytesInput('input.mp4', video)],
          outputs: const [FfmpegOutput('probe.json')],
        ),
      );

      expect(probe.isSuccess, isTrue, reason: _resultDiagnostics(probe));
      expect(
        utf8.decode(probe.outputBytes['probe.json']!),
        contains('"duration"'),
      );
      expect(_workspaces('live_render'), before);
    },
  );

  _liveTest('real process execution can be cancelled', () async {
    final before = _workspaces('live_cancel');
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);
    await ffmpeg.initialize();
    final execution = ffmpeg.execute(
      FfmpegJob(
        id: 'live_cancel',
        arguments: const [
          '-re',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=s=160x90:r=25:d=5',
          '-f',
          'null',
          '-',
        ],
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await ffmpeg.cancel();
    final result = await execution;

    expect(result.cancelled, isTrue, reason: result.logs.join('\n'));
    expect(_workspaces('live_cancel'), before);
  });

  _liveTest('real process execution enforces its timeout', () async {
    final before = _workspaces('live_timeout');
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);
    await ffmpeg.initialize();
    final result = await ffmpeg.execute(
      FfmpegJob(
        id: 'live_timeout',
        timeout: const Duration(milliseconds: 300),
        arguments: const [
          '-re',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=s=160x90:r=25:d=5',
          '-f',
          'null',
          '-',
        ],
      ),
    );

    expect(result.timedOut, isTrue, reason: result.logs.join('\n'));
    expect(_workspaces('live_timeout'), before);
  });

  _liveTest(
    'real process output quotas stop generation before completion',
    () async {
      final before = _workspaces('live_output_quota');
      final ffmpeg = UniversalFfmpeg(configuration: configuration);
      addTearDown(ffmpeg.dispose);
      await ffmpeg.initialize();

      await expectLater(
        ffmpeg.execute(
          FfmpegJob(
            id: 'live_output_quota',
            arguments: const [
              '-re',
              '-f',
              'lavfi',
              '-i',
              'testsrc2=s=640x360:r=30:d=30',
              '-c:v',
              'mpeg2video',
              '-f',
              'mpegts',
              'output.ts',
            ],
            outputs: const [FfmpegOutput('output.ts', maxBytes: 1024)],
          ),
        ),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.outputTooLarge,
          ),
        ),
      );

      expect(_workspaces('live_output_quota'), before);
    },
  );

  _liveTest(
    'destination overwrite is denied by default and explicit when enabled',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'ii_ffmpeg_universal_destination_test_',
      );
      const markerValue = 'ii-ffmpeg-universal-live-test';
      final marker = File('${owned.path}/.ii-disposable-owner');
      await marker.writeAsString(markerValue);
      addTearDown(() async {
        if (await marker.exists() &&
            await marker.readAsString() == markerValue) {
          await owned.delete(recursive: true);
        }
      });
      final destination = File('${owned.path}/rendered.bmp');
      await destination.writeAsString('keep-me');
      final ffmpeg = UniversalFfmpeg(configuration: configuration);
      addTearDown(ffmpeg.dispose);
      await ffmpeg.initialize();

      FfmpegJob job({required bool overwrite}) => FfmpegJob(
        id: overwrite ? 'live_destination_overwrite' : 'live_destination_deny',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=c=green:s=16x16:d=0.1',
          '-frames:v',
          '1',
          '-f',
          'image2',
          'output.bmp',
        ],
        outputs: [
          FfmpegOutput(
            'output.bmp',
            destinationPath: destination.path,
            captureBytes: false,
          ),
        ],
        overwriteOutput: overwrite,
      );

      await expectLater(
        ffmpeg.execute(job(overwrite: false)),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.outputExists,
          ),
        ),
      );
      expect(await destination.readAsString(), 'keep-me');

      final result = await ffmpeg.execute(job(overwrite: true));
      expect(result.isSuccess, isTrue, reason: result.logs.join('\n'));
      expect(await destination.length(), greaterThan(100));
    },
  );

  _liveTest(
    'destination appearing during execution is preserved atomically',
    () async {
      final owned = await _ownedTestDirectory('destination_race');
      final destination = File('${owned.path}/rendered.mp4');
      final ffmpeg = UniversalFfmpeg(configuration: configuration);
      addTearDown(ffmpeg.dispose);
      await ffmpeg.initialize();
      final execution = ffmpeg.execute(
        FfmpegJob(
          id: 'live_destination_race',
          arguments: const [
            '-re',
            '-f',
            'lavfi',
            '-i',
            'color=c=purple:s=32x32:r=10:d=0.8',
            '-c:v',
            'mpeg4',
            '-f',
            'mp4',
            'output.mp4',
          ],
          outputs: [
            FfmpegOutput(
              'output.mp4',
              destinationPath: destination.path,
              captureBytes: false,
            ),
          ],
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 150));
      await destination.writeAsString('created-by-another-owner');
      await expectLater(
        execution,
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.outputExists,
          ),
        ),
      );
      expect(await destination.readAsString(), 'created-by-another-owner');
      expect(
        owned.listSync().whereType<File>().map((file) => file.path),
        everyElement(isNot(contains('.partial'))),
      );
    },
  );

  _liveTest('busy, cancellation, and dispose are job scoped', () async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    await ffmpeg.initialize();
    final first = ffmpeg.execute(_slowNullJob('live_lifecycle'));

    await expectLater(
      ffmpeg.execute(_slowNullJob('live_concurrent')),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.busy,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await ffmpeg.dispose();
    final result = await first;
    expect(result.cancelled, isTrue, reason: result.logs.join('\n'));
    await expectLater(
      ffmpeg.execute(_slowNullJob('live_after_dispose')),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.disposed,
        ),
      ),
    );
  });

  _liveTest('path input is isolated from later caller mutation', () async {
    final owned = await _ownedTestDirectory('path_input');
    final source = File('${owned.path}/source.wav');
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);
    await ffmpeg.initialize();
    final generated = await ffmpeg.execute(
      FfmpegJob(
        id: 'live_path_source',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=880:sample_rate=44100:duration=1',
          '-c:a',
          'pcm_s16le',
          '-f',
          'wav',
          'source.wav',
        ],
        outputs: const [FfmpegOutput('source.wav')],
      ),
    );
    expect(generated.isSuccess, isTrue, reason: _resultDiagnostics(generated));
    await source.writeAsBytes(
      generated.outputBytes['source.wav']!,
      flush: true,
    );
    final originalLength = await source.length();
    final originalSha256 = await _sha256File(source.path);
    final execution = ffmpeg.execute(
      FfmpegJob(
        id: 'live_path_copy',
        arguments: const [
          '-re',
          '-f',
          'wav',
          '-i',
          'source.wav',
          '-c:a',
          'aac',
          '-f',
          'mp4',
          'output.m4a',
        ],
        inputs: [FfmpegPathInput('source.wav', source.path)],
        outputs: const [FfmpegOutput('output.m4a')],
      ),
    );

    await _waitForIsolatedPathInput(
      jobId: 'live_path_copy',
      inputName: 'source.wav',
      expectedLength: originalLength,
      expectedSha256: originalSha256,
    );
    await source.writeAsString('caller-mutated-source');
    final result = await execution;
    expect(result.isSuccess, isTrue, reason: result.logs.join('\n'));
    expect(result.outputBytes['output.m4a']!.length, greaterThan(1000));
    expect(await source.length(), isNot(originalLength));
  });

  _liveTest(
    'path inputs reject links and special files without blocking',
    () async {
      if (Platform.isWindows) return;
      final owned = await _ownedTestDirectory('special_input');
      final fifo = '${owned.path}/input.pipe';
      final created = await Process.run('mkfifo', [fifo]);
      expect(created.exitCode, 0, reason: '${created.stderr}');
      final source = File('${owned.path}/source.mov');
      await source.writeAsBytes([0, 1, 2, 3]);
      final link = '${owned.path}/input.link';
      await Link(link).create(source.path);
      final ffmpeg = UniversalFfmpeg(configuration: configuration);
      addTearDown(ffmpeg.dispose);
      await ffmpeg.initialize();

      for (final entry in {'input.pipe': fifo, 'input.link': link}.entries) {
        await expectLater(
          ffmpeg
              .execute(
                FfmpegJob(
                  id: 'live_special_input_${entry.key}',
                  arguments: [
                    '-f',
                    'mov',
                    '-i',
                    entry.key,
                    '-f',
                    'mp4',
                    'output.mp4',
                  ],
                  inputs: [FfmpegPathInput(entry.key, entry.value)],
                  outputs: const [FfmpegOutput('output.mp4')],
                ),
              )
              .timeout(const Duration(seconds: 2)),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.invalidJob,
            ),
          ),
          reason: entry.key,
        );
      }
    },
  );

  _registerLiveProcessSecurityTests(() => configuration);
}

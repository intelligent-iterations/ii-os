part of 'live_process_e2e_test.dart';

void _registerLiveProcessSecurityTests(
  FfmpegConfiguration Function() configuration,
) {
  _liveTest(
    'playlist demuxers that can open nested resources are rejected',
    () async {
      final ffmpeg = UniversalFfmpeg(configuration: configuration());
      addTearDown(ffmpeg.dispose);
      for (final entry in {
        'network': 'http://127.0.0.1:9/segment.ts',
        'stream': 'pipe:0',
      }.entries) {
        final playlist = Uint8List.fromList(
          utf8.encode(
            '#EXTM3U\n'
            '#EXT-X-VERSION:3\n'
            '#EXT-X-TARGETDURATION:1\n'
            '#EXT-X-MEDIA-SEQUENCE:0\n'
            '#EXTINF:1.0,\n'
            '${entry.value}\n'
            '#EXT-X-ENDLIST\n',
          ),
        );

        await expectLater(
          ffmpeg.execute(
            FfmpegJob(
              id: 'nested_${entry.key}',
              arguments: const [
                '-f',
                'hls',
                '-i',
                'playlist.m3u8',
                '-f',
                'null',
                '-',
              ],
              inputs: [FfmpegBytesInput('playlist.m3u8', playlist)],
            ),
          ),
          throwsA(
            isA<FfmpegException>().having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.unsafeArgument,
            ),
          ),
          reason: entry.key,
        );
      }
    },
  );

  _liveTest(
    'indexed unsafe filters fail before a workspace or engine starts',
    () async {
      final before = _workspaces('indexed_filter_reject');
      final ffmpeg = UniversalFfmpeg(configuration: configuration());
      addTearDown(ffmpeg.dispose);

      await expectLater(
        ffmpeg.execute(
          FfmpegJob(
            id: 'indexed_filter_reject',
            arguments: const [
              '-f',
              'lavfi',
              '-i',
              'color=black:s=16x16:d=0.1',
              '-filter:v:0',
              'metadata=mode=print:file=side.txt',
              '-f',
              'null',
              '-',
            ],
          ),
        ),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.unsafeArgument,
          ),
        ),
      );
      expect(_workspaces('indexed_filter_reject'), before);
    },
  );
}

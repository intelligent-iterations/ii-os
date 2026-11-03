import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/video_project.dart';
import 'package:ii_os/services/editor_media_source.dart';

void main() {
  test('detects bounded editor container signatures', () {
    expect(
      detectEditorMediaContentType(
        Uint8List.fromList([0, 0, 0, 24, ...'ftypisom'.codeUnits]),
      ),
      'video/mp4',
    );
    expect(
      detectEditorMediaContentType(
        Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3]),
      ),
      'video/webm',
    );
    expect(
      detectEditorMediaContentType(
        Uint8List.fromList('RIFF0000WAVE'.codeUnits),
      ),
      'audio/wav',
    );
    expect(
      detectEditorMediaContentType(Uint8List.fromList('ID3metadata'.codeUnits)),
      'audio/mpeg',
    );
    expect(
      detectEditorMediaContentType(Uint8List.fromList('fLaCdata'.codeUnits)),
      'audio/flac',
    );
    expect(
      detectEditorMediaContentType(
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
      ),
      'image/jpeg',
    );
    expect(
      detectEditorMediaContentType(
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
      'image/png',
    );
    expect(detectEditorMediaContentType(Uint8List.fromList([1, 2, 3])), isNull);
    expect(editorMediaDemuxer('audio/flac'), 'flac');
    expect(editorMediaExtension('audio/flac'), 'flac');
  });

  test('parses exact per-stream PTS, duration, and shared sync origin', () {
    final probe = parseEditorMediaProbe({
      'format': {'start_time': '1.000000', 'duration': '4.250000'},
      'streams': [
        {
          'index': 0,
          'codec_type': 'video',
          'time_base': '1/90000',
          'start_pts': 90000,
          'duration_ts': 270000,
          'start_time': '9.000000',
          'duration': '1.000000',
          'width': 1920,
          'height': 1080,
        },
        {
          'index': 1,
          'codec_type': 'audio',
          'time_base': '1/48000',
          'start_pts': 57600,
          'duration_ts': 134400,
          'start_time': '9.000000',
          'duration': '1.000000',
        },
      ],
    });

    expect(probe.hasVideo, isTrue);
    expect(probe.hasAudio, isTrue);
    expect(probe.width, 1920);
    expect(probe.height, 1080);
    expect(
      probe.videoTiming,
      const VideoProjectStreamTiming(
        presentationStart: Duration.zero,
        duration: Duration(seconds: 3),
      ),
    );
    expect(
      probe.audioTiming,
      const VideoProjectStreamTiming(
        presentationStart: Duration(milliseconds: 200),
        duration: Duration(milliseconds: 2800),
      ),
    );
    expect(probe.syncOrigin, Duration.zero);
    expect(probe.duration, const Duration(seconds: 3));
  });

  test('normalizes negative PTS while retaining inter-stream skew', () {
    final probe = parseEditorMediaProbe({
      'format': {'start_time': '-0.500000', 'duration': '2.000000'},
      'streams': [
        {
          'codec_type': 'video',
          'time_base': '1/1000',
          'start_pts': -500,
          'duration_ts': 2000,
          'width': 640,
          'height': 360,
        },
        {
          'codec_type': 'audio',
          'time_base': '1/1000',
          'start_pts': -325,
          'duration_ts': 1825,
        },
      ],
    });

    expect(probe.videoTiming!.presentationStart, Duration.zero);
    expect(
      probe.audioTiming!.presentationStart,
      const Duration(milliseconds: 175),
    );
    expect(probe.duration, const Duration(seconds: 2));
  });

  test('rounds exact PTS after subtracting the shared rational origin', () {
    final probe = parseEditorMediaProbe({
      'streams': [
        {
          'codec_type': 'video',
          'time_base': '1/90000',
          'start_pts': 4,
          'duration_ts': 90000,
          'width': 320,
          'height': 180,
        },
        {
          'codec_type': 'audio',
          'time_base': '1/90000',
          'start_pts': 5,
          'duration_ts': 89999,
        },
      ],
    });

    expect(probe.videoTiming!.presentationStart, Duration.zero);
    expect(
      probe.audioTiming!.presentationStart,
      const Duration(microseconds: 11),
    );
    expect(probe.duration, const Duration(seconds: 1));
  });

  test('retains small skew between very large exact PTS values', () {
    final probe = parseEditorMediaProbe({
      'streams': [
        {
          'codec_type': 'video',
          'time_base': '1/1000',
          'start_pts': '9223372036854775807000',
          'duration_ts': 1000,
          'width': 320,
          'height': 180,
        },
        {
          'codec_type': 'audio',
          'time_base': '1/1000',
          'start_pts': '9223372036854775807001',
          'duration_ts': 999,
        },
      ],
    });

    expect(probe.videoTiming!.presentationStart, Duration.zero);
    expect(
      probe.audioTiming!.presentationStart,
      const Duration(milliseconds: 1),
    );
    expect(probe.duration, const Duration(seconds: 1));
  });

  test('uses the first typed stream and bounded metadata fallbacks', () {
    final probe = parseEditorMediaProbe({
      'format': {'start_time': '0.500000', 'duration': '4.000000'},
      'streams': [
        {
          'index': 0,
          'codec_type': 'video',
          'start_time': '0.700000',
          'duration': '2.250000',
          'width': 640,
          'height': 360,
        },
        {
          'index': 1,
          'codec_type': 'video',
          'start_time': '1.500000',
          'duration': '0.500000',
          'width': 1920,
          'height': 1080,
        },
        {'index': 2, 'codec_type': 'audio', 'start_time': '0.500000'},
      ],
    });

    expect(probe.width, 640);
    expect(probe.height, 360);
    expect(
      probe.videoTiming!.presentationStart,
      const Duration(milliseconds: 200),
    );
    expect(probe.videoTiming!.duration, const Duration(milliseconds: 2250));
    expect(probe.audioTiming!.presentationStart, Duration.zero);
    expect(probe.audioTiming!.duration, const Duration(seconds: 4));
    expect(probe.duration, const Duration(seconds: 4));
  });

  test('normalizes presentation against selected streams, not format gap', () {
    final probe = parseEditorMediaProbe({
      'format': {'start_time': '0', 'duration': '1210'},
      'streams': [
        {
          'index': 0,
          'codec_type': 'video',
          'start_time': '10',
          'duration': '1200',
          'width': 640,
          'height': 360,
        },
      ],
    });

    expect(probe.videoTiming!.presentationStart, Duration.zero);
    expect(probe.videoTiming!.duration, const Duration(minutes: 20));
    expect(probe.duration, const Duration(minutes: 20));
  });

  test('uses format duration without start for nonpositive stream ticks', () {
    for (final durationTicks in [0, -1]) {
      final probe = parseEditorMediaProbe({
        'format': {'duration': '2.500000'},
        'streams': [
          {
            'index': 0,
            'codec_type': 'video',
            'time_base': '1/1000',
            'duration_ts': durationTicks,
            'width': 640,
            'height': 360,
          },
        ],
      });

      expect(
        probe.videoTiming!.duration,
        const Duration(milliseconds: 2500),
        reason: 'duration_ts=$durationTicks',
      );
    }
  });

  test(
    'bounds late missing stream duration by the selected format envelope',
    () {
      final probe = parseEditorMediaProbe({
        'format': {'duration': '2.000000'},
        'streams': [
          {
            'codec_type': 'video',
            'time_base': '1/1000',
            'start_pts': 1000,
            'width': 320,
            'height': 180,
          },
          {'codec_type': 'audio', 'time_base': '1/1000', 'start_pts': 1175},
        ],
      });

      expect(probe.videoTiming!.duration, const Duration(seconds: 2));
      expect(
        probe.audioTiming!.presentationStart,
        const Duration(milliseconds: 175),
      );
      expect(probe.audioTiming!.duration, const Duration(milliseconds: 1825));
      expect(probe.duration, const Duration(seconds: 2));
    },
  );

  test('ignores malformed duration timebases in favor of stream duration', () {
    for (final timeBase in ['0/1000', '-1/1000', 'invalid']) {
      final probe = parseEditorMediaProbe({
        'streams': [
          {
            'codec_type': 'audio',
            'time_base': timeBase,
            'duration_ts': 2500,
            'duration': '1.250000',
          },
        ],
      });

      expect(
        probe.audioTiming!.duration,
        const Duration(milliseconds: 1250),
        reason: 'time_base=$timeBase',
      );
    }
  });

  test('rejects absent and over-limit durations', () {
    expect(
      () => parseEditorMediaProbe({
        'format': {'duration': 'N/A'},
        'streams': [
          {'codec_type': 'video'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => parseEditorMediaProbe({
        'format': {'start_time': '0', 'duration': '${20 * 60 + 0.001}'},
        'streams': [
          {'codec_type': 'audio'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => parseEditorMediaProbe({
        'format': {'duration': '1e308'},
        'streams': [
          {'codec_type': 'video'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('saved media timing round-trips and legacy records remain readable', () {
    const videoTiming = VideoProjectStreamTiming(
      presentationStart: Duration.zero,
      duration: Duration(seconds: 2),
    );
    const audioTiming = VideoProjectStreamTiming(
      presentationStart: Duration(milliseconds: 175),
      duration: Duration(milliseconds: 1825),
    );
    const origin = WorkspaceSourceAssetOrigin('asset-1');
    const record = VideoProjectMediaRecord(
      id: 'media-1',
      filename: 'linked.mp4',
      contentType: 'video/mp4',
      byteLength: 12,
      duration: Duration(seconds: 2),
      hasVideo: true,
      hasAudio: true,
      videoTiming: videoTiming,
      audioTiming: audioTiming,
      origin: origin,
    );

    final restored = VideoProjectMediaRecord.fromJson(record.toJson());
    final legacy = VideoProjectMediaRecord.fromJson({
      ...record.toJson(),
      'videoTiming': null,
      'audioTiming': null,
    });

    expect(restored.videoTiming, videoTiming);
    expect(restored.audioTiming, audioTiming);
    expect(legacy.videoTiming, isNull);
    expect(legacy.audioTiming, isNull);
  });

  test('local media rejects inconsistent decoded timing', () {
    LocalEditorMedia local({
      required Duration duration,
      required bool hasVideo,
      required bool hasAudio,
      VideoProjectStreamTiming? videoTiming,
      VideoProjectStreamTiming? audioTiming,
    }) => LocalEditorMedia(
      id: 'timing-check',
      filename: 'timing-check.mp4',
      path: '',
      bytes: Uint8List.fromList([0, 0, 0, 24, ...'ftypisom'.codeUnits]),
      contentType: 'video/mp4',
      duration: duration,
      hasVideo: hasVideo,
      hasAudio: hasAudio,
      videoTiming: videoTiming,
      audioTiming: audioTiming,
    );

    expect(
      () => local(
        duration: const Duration(seconds: 1),
        hasVideo: false,
        hasAudio: true,
        videoTiming: const VideoProjectStreamTiming(
          presentationStart: Duration.zero,
          duration: Duration(seconds: 1),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => local(
        duration: const Duration(seconds: 1),
        hasVideo: true,
        hasAudio: false,
        videoTiming: const VideoProjectStreamTiming(
          presentationStart: Duration(milliseconds: 100),
          duration: Duration(seconds: 1),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => local(
        duration: const Duration(seconds: 2),
        hasVideo: true,
        hasAudio: false,
        videoTiming: const VideoProjectStreamTiming(
          presentationStart: Duration.zero,
          duration: Duration(seconds: 1),
        ),
      ),
      throwsArgumentError,
    );
    final overTargetDuration =
        maxEditorDuration + const Duration(microseconds: 1);
    expect(
      local(
        duration: overTargetDuration,
        hasVideo: true,
        hasAudio: false,
        videoTiming: VideoProjectStreamTiming(
          presentationStart: Duration.zero,
          duration: overTargetDuration,
        ),
      ).duration,
      overTargetDuration,
    );
  });

  test('saved stream timing rejects malformed or ambiguous integer fields', () {
    for (final value in <Map<String, Object?>>[
      {'durationMicros': 1000},
      {'presentationStartMicros': '0', 'durationMicros': 1000},
      {'presentationStartMicros': 0.0, 'durationMicros': 1000},
      {'presentationStartMicros': 0, 'durationMicros': 1000.5},
      {'presentationStartMicros': -1, 'durationMicros': 1000},
      {'presentationStartMicros': 0, 'durationMicros': 0},
      {
        'presentationStartMicros': 0,
        'durationMicros': 1000,
        'unexpected': true,
      },
    ]) {
      expect(
        () => VideoProjectStreamTiming.fromJson(value),
        throwsA(isA<FormatException>()),
        reason: '$value',
      );
    }
  });

  test('saved media rejects malformed or inconsistent timing envelopes', () {
    const record = VideoProjectMediaRecord(
      id: 'media-1',
      filename: 'linked.mp4',
      contentType: 'video/mp4',
      byteLength: 12,
      duration: Duration(seconds: 2),
      hasVideo: true,
      hasAudio: false,
      videoTiming: VideoProjectStreamTiming(
        presentationStart: Duration.zero,
        duration: Duration(seconds: 2),
      ),
      origin: WorkspaceSourceAssetOrigin('asset-1'),
    );
    final json = record.toJson();
    for (final value in ['bad', 1, true, <Object?>[]]) {
      expect(
        () => VideoProjectMediaRecord.fromJson({...json, 'videoTiming': value}),
        throwsFormatException,
        reason: '$value',
      );
    }
    expect(
      () => VideoProjectMediaRecord.fromJson({...json, 'hasVideo': false}),
      throwsFormatException,
    );
    expect(
      () => VideoProjectMediaRecord.fromJson({
        ...json,
        'durationMicros': const Duration(seconds: 1).inMicroseconds,
      }),
      throwsFormatException,
    );
    expect(
      () => VideoProjectMediaRecord.fromJson({
        ...json,
        'durationMicros': const Duration(seconds: 3).inMicroseconds,
      }),
      throwsFormatException,
    );
    expect(
      () => VideoProjectMediaRecord.fromJson({
        ...json,
        'durationMicros': const Duration(seconds: 2).inMicroseconds.toDouble(),
      }),
      throwsFormatException,
    );
    expect(
      () => VideoProjectMediaRecord.fromJson({...json, 'hasAudio': true}),
      throwsFormatException,
    );
  });

  test('recorded-real linked fixture proves the captured timing contract', () {
    const root = 'test/fixtures/video_editor/media/linked-offset-v1';
    final provenance =
        (jsonDecode(File('$root/provenance.json').readAsStringSync()) as Map)
            .cast<String, Object?>();
    final probeBytes = File('$root/ffprobe.json').readAsBytesSync();
    final mediaBytes = File('$root/linked-offset.mov').readAsBytesSync();
    final captured = jsonDecode(utf8.decode(probeBytes)) as Map;
    final streams = (captured['streams'] as List<Object?>)
        .map((value) => (value as Map).cast<String, Object?>())
        .toList(growable: false);
    final probe = parseEditorMediaProbe(captured);

    expect(provenance['classification'], 'recorded-real');
    expect(provenance['mediaSha256'], sha256.convert(mediaBytes).toString());
    expect(provenance['ffprobeSha256'], sha256.convert(probeBytes).toString());
    expect(streams[0]['start_time'], '1.000000');
    expect(streams[1]['start_time'], '1.175000');
    expect(probe.videoTiming!.presentationStart, Duration.zero);
    expect(probe.videoTiming!.duration, const Duration(seconds: 2));
    expect(
      probe.audioTiming!.presentationStart,
      const Duration(milliseconds: 175),
    );
    expect(probe.audioTiming!.duration, const Duration(milliseconds: 1825));
    expect(probe.duration, const Duration(seconds: 2));
  });

  test('accepts bounded image dimensions and rejects oversized images', () {
    expect(
      parseEditorImageProbe({
        'streams': [
          {'codec_type': 'video', 'width': 1280, 'height': 720},
        ],
      }),
      (width: 1280, height: 720),
    );
    expect(
      () => parseEditorImageProbe({
        'streams': [
          {'codec_type': 'video', 'width': 8192, 'height': 8192},
        ],
      }),
      throwsFormatException,
    );
  });
}

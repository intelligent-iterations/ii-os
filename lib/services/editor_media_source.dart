import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import '../models/video_project.dart';
import 'source_asset_uploader.dart';
import 'video_editor_ffmpeg.dart';

part 'editor_media_source_image.dart';
part 'editor_media_source_timing.dart';

final int maxEditorSourceBytes = videoEditorRenderTarget.maxSourceBytes;
final int maxEditorTotalSourceBytes =
    videoEditorRenderTarget.maxDeclaredMediaBytes;
final int maxEditorOutputBytes = videoEditorRenderTarget.maxOutputBytes;
final Duration maxEditorDuration =
    videoEditorRenderTarget.editorLimits.maxDuration;
const Duration editorStillImageDuration = Duration(seconds: 3);

String get editorLocalLimitsDescription => kIsWeb
    ? '112 MB per source and total, 64 MB output, and 2 minutes.'
    : '128 MB per source, 256 MB total source bytes, 512 MB output, and '
          '20 minutes.';

final class LocalEditorMedia {
  LocalEditorMedia({
    required this.id,
    required this.filename,
    required this.path,
    required this.bytes,
    required this.contentType,
    required this.duration,
    required this.hasVideo,
    required this.hasAudio,
    VideoProjectStreamTiming? videoTiming,
    VideoProjectStreamTiming? audioTiming,
    this.width,
    this.height,
  }) : videoTiming =
           videoTiming ??
           (hasVideo
               ? VideoProjectStreamTiming(
                   presentationStart: Duration.zero,
                   duration: duration,
                 )
               : null),
       audioTiming =
           audioTiming ??
           (hasAudio
               ? VideoProjectStreamTiming(
                   presentationStart: Duration.zero,
                   duration: duration,
                 )
               : null) {
    _validateStreamTiming(this.videoTiming, hasVideo, 'video');
    _validateStreamTiming(this.audioTiming, hasAudio, 'audio');
    if ((hasVideo || hasAudio) &&
        _syncOrigin(this.videoTiming, this.audioTiming) != Duration.zero) {
      throw ArgumentError.value(
        [this.videoTiming, this.audioTiming],
        'streamTiming',
        'must be relative to the earliest selected stream',
      );
    }
    if ((hasVideo || hasAudio) &&
        _presentationDuration(this.videoTiming, this.audioTiming) != duration) {
      throw ArgumentError.value(
        duration,
        'duration',
        'must match the decoded stream presentation duration',
      );
    }
  }

  final String id;
  final String filename;
  final String path;
  final Uint8List bytes;
  final String contentType;
  final Duration duration;
  final bool hasVideo;
  final bool hasAudio;
  final VideoProjectStreamTiming? videoTiming;
  final VideoProjectStreamTiming? audioTiming;
  final int? width;
  final int? height;

  Duration get syncOrigin => _syncOrigin(videoTiming, audioTiming);

  String get fileExtension => editorMediaExtension(contentType);

  late final MediaSource source = MediaSource(
    id: id,
    byteLength: bytes.length,
    fileExtension: fileExtension,
    openRead: () => Stream<List<int>>.value(bytes),
  );
}

final class EditorMediaProbe {
  const EditorMediaProbe({
    this.videoTiming,
    this.audioTiming,
    this.width,
    this.height,
  });

  final VideoProjectStreamTiming? videoTiming;
  final VideoProjectStreamTiming? audioTiming;
  final int? width;
  final int? height;

  bool get hasVideo => videoTiming != null;
  bool get hasAudio => audioTiming != null;
  Duration get syncOrigin => _syncOrigin(videoTiming, audioTiming);
  Duration get duration => _presentationDuration(videoTiming, audioTiming);
}

Future<LocalEditorMedia> prepareLocalEditorMedia({
  required UniversalFfmpeg ffmpeg,
  required String id,
  required String filename,
  required String path,
  required Uint8List bytes,
  String? expectedContentType,
}) async {
  if (bytes.isEmpty || bytes.length > maxEditorSourceBytes) {
    throw const FormatException(
      'The local editor source is outside its limit.',
    );
  }
  final detected = detectEditorMediaContentType(bytes);
  if (detected == null ||
      (expectedContentType != null &&
          !_compatibleEditorContentTypes(expectedContentType, detected))) {
    throw const FormatException(
      'Use a supported MP4, WebM, M4A, MP3, WAV, FLAC, JPEG, PNG, or WebP '
      'file.',
    );
  }
  var preparedBytes = Uint8List.fromList(bytes).asUnmodifiableView();
  if (detected.startsWith('image/')) {
    return _prepareStillEditorMedia(
      ffmpeg: ffmpeg,
      id: id,
      filename: filename,
      path: path,
      bytes: preparedBytes,
      contentType: detected,
    );
  }
  final probe = await probeEditorMedia(
    ffmpeg: ffmpeg,
    id: id,
    bytes: preparedBytes,
    contentType: detected,
  );
  final contentType = detected == 'video/mp4' && !probe.hasVideo
      ? 'audio/mp4'
      : detected;
  return LocalEditorMedia(
    id: id,
    filename: filename,
    path: path,
    bytes: preparedBytes,
    contentType: contentType,
    duration: probe.duration,
    hasVideo: probe.hasVideo,
    hasAudio: probe.hasAudio,
    videoTiming: probe.videoTiming,
    audioTiming: probe.audioTiming,
    width: probe.width,
    height: probe.height,
  );
}

Future<EditorMediaProbe> probeEditorMedia({
  required UniversalFfmpeg ffmpeg,
  required String id,
  required Uint8List bytes,
  required String contentType,
}) async {
  final inputName = '$id.${editorMediaExtension(contentType)}';
  const outputName = 'probe.json';
  final result = await ffmpeg.execute(
    FfmpegJob(
      id: 'probe-$id',
      operation: FfmpegOperation.ffprobe,
      arguments: [
        '-v',
        'error',
        '-show_entries',
        'format=start_time,duration:'
            'stream=index,codec_type,time_base,start_pts,duration_ts,'
            'start_time,duration,width,height',
        '-of',
        'json',
        '-f',
        editorMediaDemuxer(contentType),
        '-i',
        inputName,
        '-o',
        outputName,
      ],
      inputs: [FfmpegBytesInput(inputName, bytes)],
      outputs: const [FfmpegOutput(outputName, maxBytes: 256 * 1024)],
      timeout: const Duration(minutes: 2),
    ),
  );
  final output = result.outputBytes[outputName];
  if (!result.isSuccess || output == null) {
    throw FormatException(
      'FFprobe could not read this local media file (${result.exitCode}).',
    );
  }
  return parseEditorMediaProbe(jsonDecode(utf8.decode(output)));
}

String? detectEditorMediaContentType(Uint8List bytes) {
  final imageType = sourceImageContentType(bytes);
  if (imageType != null) return imageType;
  if (bytes.length >= 12 && _ascii(bytes, 4, 8) == 'ftyp') {
    return 'video/mp4';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x1a &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xdf &&
      bytes[3] == 0xa3) {
    return 'video/webm';
  }
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 12) == 'WAVE') {
    return 'audio/wav';
  }
  if (bytes.length >= 4 && _ascii(bytes, 0, 4) == 'fLaC') {
    return 'audio/flac';
  }
  if (bytes.length >= 3 && _ascii(bytes, 0, 3) == 'ID3') {
    return 'audio/mpeg';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
    return 'audio/mpeg';
  }
  return null;
}

String editorMediaDemuxer(String contentType) => switch (contentType) {
  'video/mp4' || 'audio/mp4' => 'mov',
  'video/webm' => 'matroska',
  'audio/mpeg' => 'mp3',
  'audio/wav' => 'wav',
  'audio/flac' => 'flac',
  'image/jpeg' || 'image/png' || 'image/webp' => 'image2',
  _ => throw FormatException('Unsupported editor media type: $contentType'),
};

String editorMediaExtension(String contentType) => switch (contentType) {
  'video/mp4' => 'mp4',
  'audio/mp4' => 'm4a',
  'video/webm' => 'webm',
  'audio/mpeg' => 'mp3',
  'audio/wav' => 'wav',
  'audio/flac' => 'flac',
  'image/jpeg' => 'jpg',
  'image/png' => 'png',
  'image/webp' => 'webp',
  _ => throw FormatException('Unsupported editor media type: $contentType'),
};

bool _compatibleEditorContentTypes(String expected, String detected) {
  if (expected == detected) return true;
  return expected == 'audio/mp4' && detected == 'video/mp4';
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));

int? _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

void _validateStreamTiming(
  VideoProjectStreamTiming? timing,
  bool expected,
  String kind,
) {
  if ((timing != null) != expected ||
      (timing != null &&
          (timing.presentationStart < Duration.zero ||
              timing.duration <= Duration.zero))) {
    throw ArgumentError.value(timing, '${kind}Timing', 'is inconsistent');
  }
}

Duration _syncOrigin(
  VideoProjectStreamTiming? video,
  VideoProjectStreamTiming? audio,
) {
  final starts = [
    if (video != null) video.presentationStart,
    if (audio != null) audio.presentationStart,
  ];
  if (starts.isEmpty) return Duration.zero;
  return starts.reduce((left, right) => left < right ? left : right);
}

Duration _presentationDuration(
  VideoProjectStreamTiming? video,
  VideoProjectStreamTiming? audio,
) {
  final origin = _syncOrigin(video, audio);
  final ends = [
    if (video != null) video.presentationEnd - origin,
    if (audio != null) audio.presentationEnd - origin,
  ];
  if (ends.isEmpty) return Duration.zero;
  return ends.reduce((left, right) => left > right ? left : right);
}

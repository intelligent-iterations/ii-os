part of 'editor_media_source.dart';

Future<LocalEditorMedia> _prepareStillEditorMedia({
  required UniversalFfmpeg ffmpeg,
  required String id,
  required String filename,
  required String path,
  required Uint8List bytes,
  required String contentType,
}) async {
  final inputName = '$id.${editorMediaExtension(contentType)}';
  final dimensions = await _probeEditorImage(
    ffmpeg: ffmpeg,
    id: id,
    inputName: inputName,
    bytes: bytes,
    contentType: contentType,
  );
  return LocalEditorMedia(
    id: id,
    filename: filename,
    path: path,
    bytes: bytes,
    contentType: contentType,
    duration: editorStillImageDuration,
    hasVideo: true,
    hasAudio: false,
    width: dimensions.width,
    height: dimensions.height,
  );
}

Future<({int width, int height})> _probeEditorImage({
  required UniversalFfmpeg ffmpeg,
  required String id,
  required String inputName,
  required Uint8List bytes,
  required String contentType,
}) async {
  const outputName = 'image-probe.json';
  final result = await ffmpeg.execute(
    FfmpegJob(
      id: 'image-probe-$id',
      operation: FfmpegOperation.ffprobe,
      arguments: [
        '-v',
        'error',
        '-show_entries',
        'stream=codec_type,width,height',
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
      'FFprobe could not read this local image (${result.exitCode}).',
    );
  }
  return parseEditorImageProbe(jsonDecode(utf8.decode(output)));
}

({int width, int height}) parseEditorImageProbe(Object? value) {
  const limits = EditorLimits();
  if (value is! Map || value['streams'] is! List) {
    throw const FormatException('FFprobe returned invalid image metadata.');
  }
  for (final stream in (value['streams'] as List).whereType<Map>()) {
    if (stream['codec_type'] != 'video') continue;
    final width = _positiveInt(stream['width']);
    final height = _positiveInt(stream['height']);
    if (width != null &&
        height != null &&
        width <= limits.maxDimension &&
        height <= limits.maxDimension &&
        width * height <= limits.maxCanvasPixels) {
      return (width: width, height: height);
    }
  }
  throw const FormatException(
    'The image dimensions are missing or exceed the local editor limit.',
  );
}

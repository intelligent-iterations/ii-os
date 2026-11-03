import 'dart:typed_data';

/// Bounds and argument construction shared by the web and native capture paths.
///
/// Both backends produce a PNG that the caller then uploads, so both owe the
/// same two checks: the frame is actually a PNG, and it is small enough to be
/// one. Keeping them here means the browser path and the FFmpeg path cannot
/// drift into enforcing different limits on the same artifact.

/// The largest frame either backend may return.
///
/// A single decoded frame is far smaller than this in practice; the ceiling
/// exists so a pathological source cannot turn one panel extend into a
/// hundred-megabyte upload.
const int maxVideoLastFrameBytes = 25 * 1024 * 1024;

/// Arguments that pull the last decodable frame out of [inputName].
///
/// `-sseof -0.05` seeks relative to the end rather than decoding the whole
/// file, which is what keeps this bounded on a long source. The final frame is
/// often not a keyframe, so this asks for the last 50ms and takes the first
/// frame that decodes out of it rather than seeking to an exact timestamp that
/// may not exist.
///
/// Names, not paths: the universal FFmpeg runtime maps named inputs and outputs
/// into its own owned workspace, so nothing here can reference a device path.
List<String> videoLastFrameFfmpegArguments({
  required String inputName,
  required String outputName,
}) => <String>[
  '-hide_banner',
  '-loglevel',
  'error',
  '-sseof',
  '-0.05',
  '-i',
  inputName,
  // Explicitly the first video stream: a source carrying cover art would
  // otherwise be able to hand back the album thumbnail instead of a frame.
  '-map',
  '0:v:0',
  '-frames:v',
  '1',
  '-c:v',
  'png',
  outputName,
];

/// Whether [bytes] opens with the PNG signature.
///
/// The caller uploads this as `image/png`. FFmpeg failing in a way that still
/// writes an output, or a browser canvas returning some other encoding, would
/// otherwise put a mislabelled object in the workspace bucket.
bool hasPngSignature(Uint8List bytes) {
  const signature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

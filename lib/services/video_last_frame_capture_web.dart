import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'video_last_frame_capture_limits.dart';

const Duration _videoLoadTimeout = Duration(seconds: 30);
const Duration _videoSeekTimeout = Duration(seconds: 30);

/// Captures the last decodable frame from already verified local [videoBytes].
Future<Uint8List> captureVideoLastFrame(
  Uint8List videoBytes, {
  required String contentType,
}) async {
  final blob = web.Blob(
    <JSAny>[videoBytes.toJS].toJS,
    web.BlobPropertyBag(type: contentType),
  );
  final videoUrl = web.URL.createObjectURL(blob);
  final video = web.HTMLVideoElement()
    ..muted = true
    ..preload = 'auto'
    ..src = videoUrl;
  try {
    await _waitForEvent(
      video,
      success: 'loadedmetadata',
      failure: 'error',
    ).timeout(_videoLoadTimeout);
    final duration = video.duration;
    if (duration.isNaN || !duration.isFinite || duration <= 0) {
      throw StateError('The source video has no usable duration.');
    }
    video.currentTime = (duration - 0.05).clamp(0, duration);
    await _waitForEvent(
      video,
      success: 'seeked',
      failure: 'error',
    ).timeout(_videoSeekTimeout);

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width == 0 || height == 0) {
      throw StateError('The source video has no decodable frame.');
    }

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.drawImage(video, 0, 0);

    final dataUrl = canvas.toDataURL('image/png');
    const marker = 'base64,';
    final markerIndex = dataUrl.indexOf(marker);
    if (markerIndex < 0) {
      throw StateError('The captured frame could not be encoded.');
    }
    final bytes = base64Decode(dataUrl.substring(markerIndex + marker.length));
    // The same two checks the native path owes. The caller uploads this as
    // image/png, so a canvas that handed back some other encoding, or a frame
    // large enough to matter, must not reach the workspace bucket.
    if (bytes.length > maxVideoLastFrameBytes) {
      throw const FormatException('The extracted frame is too large.');
    }
    if (!hasPngSignature(bytes)) {
      throw StateError('The browser returned an invalid PNG frame.');
    }
    return bytes;
  } finally {
    video.removeAttribute('src');
    video.load();
    web.URL.revokeObjectURL(videoUrl);
  }
}

Future<void> _waitForEvent(
  web.EventTarget target, {
  required String success,
  required String failure,
}) {
  final completer = Completer<void>();
  late final JSFunction onSuccess;
  late final JSFunction onFailure;
  void cleanup() {
    target.removeEventListener(success, onSuccess);
    target.removeEventListener(failure, onFailure);
  }

  onSuccess = ((web.Event event) {
    cleanup();
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  onFailure = ((web.Event event) {
    cleanup();
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('The video element could not load or seek the source.'),
      );
    }
  }).toJS;
  target.addEventListener(success, onSuccess);
  target.addEventListener(failure, onFailure);
  return completer.future;
}

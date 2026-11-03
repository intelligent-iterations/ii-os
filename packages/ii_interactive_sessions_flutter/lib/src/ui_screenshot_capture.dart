import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

Future<UiScreenshot> captureInteractiveSurface({
  required GlobalKey boundaryKey,
  required int revision,
  required bool redacted,
  int maxWidth = 1440,
  int maxHeight = 900,
  int maxBytes = 1024 * 1024,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
    throw StateError('Interactive surface is not ready for capture.');
  }
  final size = boundary.size;
  final ratio = [
    1.0,
    maxWidth / size.width,
    maxHeight / size.height,
  ].reduce((left, right) => left < right ? left : right);
  if (!ratio.isFinite || ratio <= 0) {
    throw StateError('Interactive surface has invalid dimensions.');
  }
  final image = await boundary.toImage(pixelRatio: ratio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data?.buffer.asUint8List();
    if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('Interactive screenshot exceeds its byte limit.');
    }
    return UiScreenshot(
      revision: revision,
      mimeType: 'image/png',
      bytes: bytes,
      redacted: redacted,
    );
  } finally {
    image.dispose();
  }
}

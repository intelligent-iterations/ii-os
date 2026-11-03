import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/rendering/cancellation.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';
import 'package:meta/meta.dart';

@immutable
final class EditorCaptionRasterRequest {
  const EditorCaptionRasterRequest({
    required this.clip,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.limits,
  });

  final EditorCaptionClip clip;
  final int canvasWidth;
  final int canvasHeight;
  final EditorLimits limits;

  int get pixelWidth {
    final rect = clip.destination;
    return ((rect.x + rect.width) * canvasWidth).round() -
        (rect.x * canvasWidth).round();
  }

  int get pixelHeight {
    final rect = clip.destination;
    return ((rect.y + rect.height) * canvasHeight).round() -
        (rect.y * canvasHeight).round();
  }
}

abstract interface class EditorCaptionRasterizer {
  Future<Uint8List> rasterize(
    EditorCaptionRasterRequest request, {
    required EditorRenderCancellationToken cancellation,
  });
}

typedef EditorCaptionRasterizeCallback =
    Future<Uint8List> Function(
      EditorCaptionRasterRequest request,
      EditorRenderCancellationToken cancellation,
    );

final class CallbackCaptionRasterizer implements EditorCaptionRasterizer {
  const CallbackCaptionRasterizer(this.callback);

  final EditorCaptionRasterizeCallback callback;

  @override
  Future<Uint8List> rasterize(
    EditorCaptionRasterRequest request, {
    required EditorRenderCancellationToken cancellation,
  }) => callback(request, cancellation);
}

final class FlutterCaptionRasterizer implements EditorCaptionRasterizer {
  const FlutterCaptionRasterizer();

  @override
  Future<Uint8List> rasterize(
    EditorCaptionRasterRequest request, {
    required EditorRenderCancellationToken cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final width = request.pixelWidth;
    final height = request.pixelHeight;
    if (width <= 0 ||
        height <= 0 ||
        width * height > request.limits.maxCaptionPixels) {
      throw EditorValidationException(
        'Caption ${request.clip.id} raster dimensions are out of bounds.',
      );
    }
    final style = request.clip.style;
    final horizontalPadding = style.horizontalPadding;
    final verticalPadding = style.verticalPadding;
    final contentWidth = width - horizontalPadding * 2;
    final contentHeight = height - verticalPadding * 2;
    if (contentWidth <= 0 || contentHeight <= 0) {
      throw EditorValidationException(
        'Caption ${request.clip.id} padding leaves no drawable area.',
      );
    }

    final painter = TextPainter(
      text: TextSpan(
        text: request.clip.text,
        style: TextStyle(
          color: ui.Color(style.textColor),
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: FontWeight.values[(style.fontWeight ~/ 100) - 1],
          height: 1.15,
        ),
      ),
      textAlign: switch (style.textAlign) {
        EditorTextAlign.left => TextAlign.left,
        EditorTextAlign.center => TextAlign.center,
        EditorTextAlign.right => TextAlign.right,
      },
      textDirection: TextDirection.ltr,
      maxLines: style.maxLines,
    );
    try {
      painter.layout(maxWidth: contentWidth);
      if (painter.didExceedMaxLines || painter.height > contentHeight) {
        throw EditorValidationException(
          'Caption ${request.clip.id} does not fit its bounded destination.',
        );
      }
      cancellation.throwIfCancelled();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..clipRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      final background = ui.Paint()..color = ui.Color(style.backgroundColor);
      if (background.color.a > 0) {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            ui.Radius.circular(style.cornerRadius),
          ),
          background,
        );
      }
      final textX = switch (style.textAlign) {
        EditorTextAlign.left => horizontalPadding,
        EditorTextAlign.center => (width - painter.width) / 2,
        EditorTextAlign.right => width - horizontalPadding - painter.width,
      };
      painter.paint(canvas, ui.Offset(textX, (height - painter.height) / 2));
      final picture = recorder.endRecording();
      ui.Image? image;
      try {
        image = await picture.toImage(width, height);
        cancellation.throwIfCancelled();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        cancellation.throwIfCancelled();
        if (data == null || data.lengthInBytes == 0) {
          throw EditorValidationException(
            'Caption ${request.clip.id} could not be encoded as PNG.',
          );
        }
        if (data.lengthInBytes > request.limits.maxCaptionRasterBytes) {
          throw EditorValidationException(
            'Caption ${request.clip.id} PNG exceeds the byte limit.',
          );
        }
        return Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image?.dispose();
        picture.dispose();
      }
    } finally {
      painter.dispose();
    }
  }
}

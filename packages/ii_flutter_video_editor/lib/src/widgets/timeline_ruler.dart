import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';

final class EditorTimelineRuler extends StatelessWidget {
  const EditorTimelineRuler({
    required this.durationSeconds,
    required this.pixelsPerSecond,
    required this.theme,
    super.key,
  });

  final double durationSeconds;
  final double pixelsPerSecond;
  final EditorThemeData theme;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _RulerPainter(
        durationSeconds: durationSeconds,
        pixelsPerSecond: pixelsPerSecond,
        theme: theme,
      ),
    ),
  );
}

final class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.durationSeconds,
    required this.pixelsPerSecond,
    required this.theme,
  });

  final double durationSeconds;
  final double pixelsPerSecond;
  final EditorThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = theme.rulerColor);
    final interval = switch (pixelsPerSecond) {
      >= 100 => 1.0,
      >= 50 => 2.0,
      >= 24 => 5.0,
      _ => 10.0,
    };
    final tick = Paint()
      ..color = theme.dividerColor
      ..strokeWidth = 1;
    final visible = canvas.getLocalClipBounds().intersect(Offset.zero & size);
    final first = math.max(
      0,
      (visible.left / pixelsPerSecond / interval).floor(),
    );
    final last = math.min(
      (durationSeconds / interval).ceil(),
      (visible.right / pixelsPerSecond / interval).ceil(),
    );
    final labels = TextPainter(textDirection: TextDirection.ltr);
    try {
      for (var index = first; index <= last; index++) {
        final seconds = math.min(index * interval, durationSeconds);
        final x = seconds * pixelsPerSecond;
        canvas.drawLine(
          Offset(x, size.height - 10),
          Offset(x, size.height),
          tick,
        );
        labels
          ..text = TextSpan(
            text: _label(seconds),
            style: TextStyle(color: theme.mutedTextColor, fontSize: 10),
          )
          ..layout();
        labels.paint(canvas, Offset(x + 4, 4));
      }
    } finally {
      labels.dispose();
    }
  }

  String _label(double seconds) {
    final total = seconds.round();
    final minutes = total ~/ 60;
    final remainder = total % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      oldDelegate.durationSeconds != durationSeconds ||
      oldDelegate.pixelsPerSecond != pixelsPerSecond ||
      oldDelegate.theme != theme;
}

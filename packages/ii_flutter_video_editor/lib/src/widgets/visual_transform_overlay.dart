import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/media.dart';

final class EditorVisualTransformOverlay extends StatefulWidget {
  const EditorVisualTransformOverlay({
    required this.destination,
    required this.enabled,
    required this.theme,
    required this.onCommitted,
    super.key,
  });

  final MediaRect destination;
  final bool enabled;
  final EditorThemeData theme;
  final ValueChanged<MediaRect> onCommitted;

  @override
  State<EditorVisualTransformOverlay> createState() =>
      _EditorVisualTransformOverlayState();
}

final class _EditorVisualTransformOverlayState
    extends State<EditorVisualTransformOverlay> {
  late MediaRect _preview = widget.destination;
  bool _dragging = false;

  @override
  void didUpdateWidget(EditorVisualTransformOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && !_sameRect(oldWidget.destination, widget.destination)) {
      _preview = widget.destination;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final canvasWidth = constraints.maxWidth;
      final canvasHeight = constraints.maxHeight;
      return Stack(
        children: [
          Positioned(
            left: _preview.x * canvasWidth,
            top: _preview.y * canvasHeight,
            width: _preview.width * canvasWidth,
            height: _preview.height * canvasHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: 'Selected image overlay',
                    hint: widget.enabled
                        ? 'Drag to position the image.'
                        : 'The image lane is locked.',
                    child: MouseRegion(
                      cursor: widget.enabled
                          ? SystemMouseCursors.move
                          : SystemMouseCursors.forbidden,
                      child: GestureDetector(
                        key: const ValueKey('editor-visual-move'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: widget.enabled ? (_) => _start() : null,
                        onPanUpdate: widget.enabled
                            ? (details) => _move(
                                details.delta,
                                canvasWidth,
                                canvasHeight,
                              )
                            : null,
                        onPanEnd: widget.enabled ? (_) => _finish() : null,
                        onPanCancel: widget.enabled ? _cancel : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: widget.theme.selectedColor,
                              width: 2,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              color: widget.theme.selectedColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Icon(
                                widget.enabled
                                    ? Icons.image_outlined
                                    : Icons.lock_outline,
                                color: widget.theme.backgroundColor,
                                size: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.enabled)
                  Positioned(
                    right: -18,
                    bottom: -18,
                    width: 40,
                    height: 40,
                    child: Semantics(
                      button: true,
                      label: 'Resize selected image overlay',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: GestureDetector(
                          key: const ValueKey('editor-visual-resize'),
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => _start(),
                          onPanUpdate: (details) =>
                              _resize(details.delta, canvasWidth, canvasHeight),
                          onPanEnd: (_) => _finish(),
                          onPanCancel: _cancel,
                          child: Center(
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: widget.theme.selectedColor,
                                border: Border.all(
                                  color: widget.theme.backgroundColor,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  void _start() => _dragging = true;

  void _move(Offset delta, double canvasWidth, double canvasHeight) {
    setState(() {
      _preview = MediaRect(
        x: (_preview.x + delta.dx / canvasWidth)
            .clamp(0.0, 1 - _preview.width)
            .toDouble(),
        y: (_preview.y + delta.dy / canvasHeight)
            .clamp(0.0, 1 - _preview.height)
            .toDouble(),
        width: _preview.width,
        height: _preview.height,
      );
    });
  }

  void _resize(Offset delta, double canvasWidth, double canvasHeight) {
    const minimum = 0.06;
    setState(() {
      _preview = MediaRect(
        x: _preview.x,
        y: _preview.y,
        width: (_preview.width + delta.dx / canvasWidth)
            .clamp(minimum, 1 - _preview.x)
            .toDouble(),
        height: (_preview.height + delta.dy / canvasHeight)
            .clamp(minimum, 1 - _preview.y)
            .toDouble(),
      );
    });
  }

  void _finish() {
    _dragging = false;
    if (!_sameRect(_preview, widget.destination)) {
      widget.onCommitted(_preview);
    }
  }

  void _cancel() {
    setState(() {
      _dragging = false;
      _preview = widget.destination;
    });
  }
}

bool _sameRect(MediaRect left, MediaRect right) =>
    left.x == right.x &&
    left.y == right.y &&
    left.width == right.width &&
    left.height == right.height;

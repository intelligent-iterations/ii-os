import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/inpaint_mask.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class ImageEditTemplateWarning extends StatelessWidget {
  const ImageEditTemplateWarning({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.circleAlert, size: 17, color: IiOsColors.amber),
        IiOsGap.hXs,
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class ImageEditPreview extends StatelessWidget {
  const ImageEditPreview({
    required this.imageBytes,
    required this.imageUrl,
    required this.aspectRatio,
    this.imageCacheKey,
    super.key,
  });

  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? imageCacheKey;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(IiOsRadii.md),
      child: AspectRatio(
        aspectRatio: aspectRatio.clamp(0.45, 2.4).toDouble(),
        child: _ImageSurface(
          imageBytes: imageBytes,
          imageUrl: imageUrl,
          imageCacheKey: imageCacheKey,
        ),
      ),
    );
  }
}

class InpaintRegionSelector extends StatefulWidget {
  const InpaintRegionSelector({
    required this.imageBytes,
    required this.imageUrl,
    required this.aspectRatio,
    required this.masks,
    required this.allowMultiple,
    required this.enabled,
    required this.onChanged,
    required this.onClear,
    this.imageCacheKey,
    super.key,
  });

  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? imageCacheKey;
  final double aspectRatio;
  final List<Rect> masks;
  final bool allowMultiple;
  final bool enabled;
  final ValueChanged<List<Rect>> onChanged;
  final VoidCallback? onClear;

  @override
  State<InpaintRegionSelector> createState() => _InpaintRegionSelectorState();
}

enum InpaintSelectionTool { rectangle, brush, erase }

class _InpaintRegionSelectorState extends State<InpaintRegionSelector> {
  Offset? _start;
  Rect? _draft;
  InpaintSelectionTool _tool = InpaintSelectionTool.rectangle;
  final List<List<Rect>> _undoStack = [];
  final List<List<Rect>> _redoStack = [];
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'inpaint-selection-shortcuts',
  );
  List<Rect>? _gestureBase;
  List<Rect>? _gestureMasks;
  Offset? _lastBrushPoint;

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxRegions = widget.allowMultiple ? maxInpaintMaskRegions : 1;
    final masks = widget.masks.take(maxRegions).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ToolChip(
              key: const ValueKey('selection-tool-rectangle'),
              label: 'Select area',
              icon: LucideIcons.scan,
              selected: _tool == InpaintSelectionTool.rectangle,
              enabled: widget.enabled,
              onSelected: () => _selectTool(InpaintSelectionTool.rectangle),
            ),
            _ToolChip(
              key: const ValueKey('selection-tool-brush'),
              label: 'Brush',
              icon: LucideIcons.paintbrush,
              selected: _tool == InpaintSelectionTool.brush,
              enabled: widget.enabled && widget.allowMultiple,
              onSelected: () => _selectTool(InpaintSelectionTool.brush),
            ),
            _ToolChip(
              key: const ValueKey('selection-tool-erase'),
              label: 'Erase',
              icon: LucideIcons.eraser,
              selected: _tool == InpaintSelectionTool.erase,
              enabled: widget.enabled && widget.allowMultiple,
              onSelected: () => _selectTool(InpaintSelectionTool.erase),
            ),
            TextButton.icon(
              key: const ValueKey('selection-undo'),
              onPressed: widget.enabled && _undoStack.isNotEmpty ? _undo : null,
              icon: const Icon(LucideIcons.undo2, size: 16),
              label: const Text('Undo'),
            ),
            TextButton.icon(
              key: const ValueKey('selection-redo'),
              onPressed: widget.enabled && _redoStack.isNotEmpty ? _redo : null,
              icon: const Icon(LucideIcons.redo2, size: 16),
              label: const Text('Redo'),
            ),
            TextButton.icon(
              key: const ValueKey('selection-clear'),
              onPressed:
                  widget.enabled && masks.isNotEmpty && widget.onClear != null
                  ? () => _clearAll(masks)
                  : null,
              icon: const Icon(LucideIcons.x, size: 16),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(switch (_tool) {
          InpaintSelectionTool.rectangle =>
            masks.isEmpty
                ? 'Drag a box around what you want to change.'
                : masks.length < maxRegions
                ? 'Drag another box to add an area. Use Cmd/Ctrl+Z to undo.'
                : 'Selection limit reached. Undo or clear an area to continue.',
          InpaintSelectionTool.brush =>
            'Paint over the parts you want changed.',
          InpaintSelectionTool.erase =>
            'Paint over highlighted selection to remove it.',
        }, style: Theme.of(context).textTheme.bodySmall),
        IiOsGap.vXs,
        ClipRRect(
          borderRadius: BorderRadius.circular(IiOsRadii.md),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio.clamp(0.45, 2.4).toDouble(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final canAddRectangle =
                    !widget.allowMultiple || masks.length < maxRegions;
                final canInteract =
                    _tool != InpaintSelectionTool.rectangle || canAddRectangle;
                return CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                        _undoShortcut,
                    const SingleActivator(
                      LogicalKeyboardKey.keyZ,
                      control: true,
                    ): _undoShortcut,
                    const SingleActivator(
                      LogicalKeyboardKey.keyZ,
                      meta: true,
                      shift: true,
                    ): _redoShortcut,
                    const SingleActivator(
                      LogicalKeyboardKey.keyZ,
                      control: true,
                      shift: true,
                    ): _redoShortcut,
                    const SingleActivator(
                      LogicalKeyboardKey.keyY,
                      control: true,
                    ): _redoShortcut,
                  },
                  child: Focus(
                    autofocus: true,
                    focusNode: _shortcutFocusNode,
                    child: GestureDetector(
                      key: const ValueKey('inpaint-mask-surface'),
                      onPanStart: widget.enabled && canInteract
                          ? (details) => _startGesture(
                              details.localPosition,
                              size,
                              masks,
                              maxRegions,
                            )
                          : null,
                      onPanUpdate: widget.enabled && canInteract
                          ? (details) => _updateGesture(
                              details.localPosition,
                              size,
                              maxRegions,
                            )
                          : null,
                      onPanEnd: widget.enabled && canInteract
                          ? (_) => _finishGesture(maxRegions)
                          : null,
                      onPanCancel: widget.enabled && canInteract
                          ? _cancelGesture
                          : null,
                      child: CustomPaint(
                        foregroundPainter: _MaskPainter([...masks, ?_draft]),
                        child: _ImageSurface(
                          imageBytes: widget.imageBytes,
                          imageUrl: widget.imageUrl,
                          imageCacheKey: widget.imageCacheKey,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _selectTool(InpaintSelectionTool tool) {
    if (_tool == tool) return;
    setState(() {
      _tool = tool;
      _clearGestureState();
    });
  }

  void _startGesture(
    Offset point,
    Size size,
    List<Rect> masks,
    int maxRegions,
  ) {
    _shortcutFocusNode.requestFocus();
    _gestureBase = List<Rect>.of(masks);
    _gestureMasks = List<Rect>.of(masks);
    _lastBrushPoint = null;
    if (_tool == InpaintSelectionTool.rectangle) {
      setState(() {
        _start = point;
        _draft = _rect(point, point, size);
      });
      return;
    }
    _paintSelection(point, size, maxRegions);
  }

  void _updateGesture(Offset point, Size size, int maxRegions) {
    if (_tool == InpaintSelectionTool.rectangle) {
      final start = _start;
      if (start == null) return;
      setState(() => _draft = _rect(start, point, size));
      return;
    }
    _paintSelection(point, size, maxRegions);
  }

  void _paintSelection(Offset point, Size size, int maxRegions) {
    final current = _gestureMasks;
    if (current == null) return;
    final last = _lastBrushPoint;
    final points = <Offset>[];
    if (last == null) {
      points.add(point);
    } else {
      final distance = (point - last).distance;
      final steps = (distance / 10).ceil().clamp(1, 20);
      for (var index = 1; index <= steps; index++) {
        points.add(Offset.lerp(last, point, index / steps)!);
      }
    }
    var next = List<Rect>.of(current);
    for (final sample in points) {
      final stamp = _brushRect(sample, size);
      next = _tool == InpaintSelectionTool.erase
          ? _eraseRect(next, stamp, maxRegions)
          : _addBrushRect(next, stamp, maxRegions);
    }
    _lastBrushPoint = point;
    _gestureMasks = next;
    widget.onChanged(List<Rect>.unmodifiable(next));
    if (mounted) setState(() {});
  }

  void _finishGesture(int maxRegions) {
    final base = _gestureBase ?? const <Rect>[];
    if (_tool == InpaintSelectionTool.rectangle) {
      final draft = _draft;
      if (draft != null && draft.width > 0 && draft.height > 0) {
        final next = widget.allowMultiple
            ? [...base, draft].take(maxRegions).toList()
            : [draft];
        _recordChange(base, next);
      }
    } else {
      final next = _gestureMasks ?? base;
      if (!listEquals(base, next)) _recordHistory(base);
    }
    setState(_clearGestureState);
  }

  void _cancelGesture() {
    final base = _gestureBase;
    if (base != null && _tool != InpaintSelectionTool.rectangle) {
      widget.onChanged(List<Rect>.unmodifiable(base));
    }
    setState(_clearGestureState);
  }

  Rect _rect(Offset start, Offset end, Size size) {
    final left = (start.dx < end.dx ? start.dx : end.dx).clamp(0, size.width);
    final top = (start.dy < end.dy ? start.dy : end.dy).clamp(0, size.height);
    final right = (start.dx > end.dx ? start.dx : end.dx).clamp(0, size.width);
    final bottom = (start.dy > end.dy ? start.dy : end.dy).clamp(
      0,
      size.height,
    );
    return Rect.fromLTRB(
      left / size.width,
      top / size.height,
      right / size.width,
      bottom / size.height,
    );
  }

  Rect _brushRect(Offset point, Size size) {
    const diameter = 30.0;
    final halfWidth = diameter / size.width / 2;
    final halfHeight = diameter / size.height / 2;
    final x = (point.dx / size.width).clamp(0.0, 1.0);
    final y = (point.dy / size.height).clamp(0.0, 1.0);
    return Rect.fromLTRB(
      (x - halfWidth).clamp(0.0, 1.0),
      (y - halfHeight).clamp(0.0, 1.0),
      (x + halfWidth).clamp(0.0, 1.0),
      (y + halfHeight).clamp(0.0, 1.0),
    );
  }

  List<Rect> _addBrushRect(List<Rect> masks, Rect stamp, int maxRegions) {
    if (masks.length >= maxRegions) return masks;
    return [...masks, stamp];
  }

  List<Rect> _eraseRect(List<Rect> masks, Rect eraser, int maxRegions) {
    final remaining = <Rect>[];
    for (final mask in masks) {
      final overlap = mask.intersect(eraser);
      if (overlap.isEmpty) {
        remaining.add(mask);
        continue;
      }
      final pieces = [
        Rect.fromLTRB(mask.left, mask.top, mask.right, overlap.top),
        Rect.fromLTRB(mask.left, overlap.bottom, mask.right, mask.bottom),
        Rect.fromLTRB(mask.left, overlap.top, overlap.left, overlap.bottom),
        Rect.fromLTRB(overlap.right, overlap.top, mask.right, overlap.bottom),
      ].where((rect) => rect.width > .002 && rect.height > .002);
      remaining.addAll(pieces);
      if (remaining.length >= maxRegions) break;
    }
    return remaining.take(maxRegions).toList(growable: false);
  }

  void _recordChange(List<Rect> previous, List<Rect> next) {
    if (listEquals(previous, next)) return;
    _recordHistory(previous);
    widget.onChanged(List<Rect>.unmodifiable(next));
  }

  void _recordHistory(List<Rect> previous) {
    _undoStack.add(List<Rect>.of(previous));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    _redoStack.add(List<Rect>.of(widget.masks));
    widget.onChanged(List<Rect>.unmodifiable(previous));
    setState(() {});
  }

  void _undoShortcut() {
    if (widget.enabled) _undo();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(List<Rect>.of(widget.masks));
    widget.onChanged(List<Rect>.unmodifiable(next));
    setState(() {});
  }

  void _redoShortcut() {
    if (widget.enabled) _redo();
  }

  void _clearAll(List<Rect> masks) {
    _recordHistory(masks);
    widget.onClear?.call();
    setState(() {});
  }

  void _clearGestureState() {
    _start = null;
    _draft = null;
    _gestureBase = null;
    _gestureMasks = null;
    _lastBrushPoint = null;
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    onSelected: enabled ? (_) => onSelected() : null,
    avatar: Icon(icon, size: 15),
    label: Text(label),
  );
}

class _MaskPainter extends CustomPainter {
  const _MaskPainter(this.masks);

  final List<Rect> masks;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.24);
    final normalized = masks
        .where((mask) => mask.width > 0 && mask.height > 0)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return;
    }
    final rects = normalized
        .map(
          (mask) => Rect.fromLTWH(
            mask.left * size.width,
            mask.top * size.height,
            mask.width * size.width,
            mask.height * size.height,
          ),
        )
        .toList(growable: false);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, overlay);
    for (final rect in rects) {
      canvas.drawRect(rect, Paint()..blendMode = BlendMode.clear);
    }
    canvas.restore();
    for (final rect in rects) {
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = IiOsColors.blue,
      );
      canvas.drawRect(
        rect,
        Paint()..color = IiOsColors.blue.withValues(alpha: 0.16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) {
    return oldDelegate.masks != masks;
  }
}

class _ImageSurface extends StatelessWidget {
  const _ImageSurface({
    required this.imageBytes,
    required this.imageUrl,
    required this.imageCacheKey,
  });

  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? imageCacheKey;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
    final url = imageUrl;
    if (url != null && url.trim().isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        cacheKey: imageCacheKey,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        useOldImageOnUrlChange: true,
        errorWidget: (context, url, error) => const _ImagePlaceholder(),
      );
    }
    return const _ImagePlaceholder();
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: IiOsColors.canvas,
      child: Center(child: Icon(LucideIcons.imageOff, color: IiOsColors.muted)),
    );
  }
}

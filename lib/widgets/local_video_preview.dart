import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/editor_media_source.dart';
import '../services/local_video_handle.dart';

final class LocalVideoPreview extends StatefulWidget {
  const LocalVideoPreview({
    required this.media,
    required this.sourcePosition,
    this.backgroundColor = Colors.black,
    this.fit = BoxFit.contain,
    this.showControls = true,
    super.key,
  });

  final LocalEditorMedia? media;
  final Duration sourcePosition;
  final Color backgroundColor;
  final BoxFit fit;
  final bool showControls;

  @override
  State<LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

final class _LocalVideoPreviewState extends State<LocalVideoPreview> {
  LocalVideoHandle? _handle;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media?.id != widget.media?.id) {
      unawaited(_load());
    } else if (oldWidget.sourcePosition != widget.sourcePosition) {
      unawaited(_seek());
    }
  }

  @override
  void dispose() {
    _epoch += 1;
    final handle = _handle;
    _handle = null;
    if (handle != null) unawaited(handle.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _handle?.controller;
    if (_error != null) {
      return Center(
        child: Text(
          'Preview unavailable\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (widget.media == null) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: Center(
          child: Text(
            'No video at this playhead',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final naturalSize = controller.value.size;
    final width = naturalSize.width > 0
        ? naturalSize.width
        : controller.value.aspectRatio * 100;
    final height = naturalSize.height > 0 ? naturalSize.height : 100.0;
    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: FittedBox(
              fit: widget.fit,
              child: SizedBox(
                width: width,
                height: height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          if (widget.showControls)
            Center(
              child: IconButton.filledTonal(
                tooltip: controller.value.isPlaying
                    ? 'Pause preview'
                    : 'Play preview',
                onPressed: () async {
                  if (controller.value.isPlaying) {
                    await controller.pause();
                  } else {
                    await controller.play();
                  }
                  if (mounted) setState(() {});
                },
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final previous = _handle;
    _handle = null;
    _error = null;
    if (mounted) setState(() {});
    if (previous != null) await previous.dispose();
    final media = widget.media;
    if (media == null || !media.hasVideo) return;
    try {
      final next = await LocalVideoHandle.create(
        path: media.path,
        bytes: media.bytes,
        contentType: media.contentType,
      );
      if (!mounted || epoch != _epoch) {
        await next.dispose();
        return;
      }
      _handle = next;
      await _seek();
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    }
  }

  Future<void> _seek() async {
    final controller = _handle?.controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    final target = widget.sourcePosition > duration
        ? duration
        : widget.sourcePosition;
    if ((controller.value.position - target).abs() >
        const Duration(milliseconds: 120)) {
      await controller.seekTo(target);
    }
  }
}

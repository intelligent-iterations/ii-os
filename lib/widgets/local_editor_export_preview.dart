import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/local_editor_export.dart';

final class LocalEditorExportPreview extends StatefulWidget {
  const LocalEditorExportPreview({required this.artifact, super.key});

  final LocalEditorExportArtifact artifact;

  @override
  State<LocalEditorExportPreview> createState() =>
      _LocalEditorExportPreviewState();
}

final class _LocalEditorExportPreviewState
    extends State<LocalEditorExportPreview> {
  VideoPlayerController? _controller;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LocalEditorExportPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.artifact, widget.artifact)) unawaited(_load());
  }

  @override
  void dispose() {
    _epoch += 1;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: Text(
          'Export ready, but local preview is unavailable.\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          Center(
            child: IconButton.filledTonal(
              tooltip: controller.value.isPlaying
                  ? 'Pause exported video'
                  : 'Play exported video',
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
          Positioned(
            left: 12,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  '${widget.artifact.byteLength} bytes · workspace asset '
                  '${widget.artifact.assetId ?? 'not uploaded'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final previous = _controller;
    _controller = null;
    _error = null;
    if (mounted) setState(() {});
    if (previous != null) await previous.dispose();
    try {
      final controller = await widget.artifact.createController();
      if (!mounted || epoch != _epoch) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() {});
    } on Object catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error);
    }
  }
}

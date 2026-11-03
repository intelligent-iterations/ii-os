import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../services/client_error_reporter.dart';
import '../services/local_video_handle.dart';
import '../services/verified_artifact_media.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'audio_player_surface.dart';

final class VerifiedArtifactImage extends StatefulWidget {
  const VerifiedArtifactImage({
    required this.media,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    super.key,
  });

  final VerifiedArtifactMedia media;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<VerifiedArtifactImage> createState() => _VerifiedArtifactImageState();
}

final class _VerifiedArtifactImageState extends State<VerifiedArtifactImage> {
  int _epoch = 0;

  ImageProvider _provider() => ResizeImage.resizeIfNeeded(
    widget.cacheWidth,
    null,
    MemoryImage(widget.media.bytes),
  );

  Future<void> _retry() async {
    await _provider().evict();
    if (mounted) setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey('verified-artifact-image-$_epoch'),
    image: _provider(),
    fit: widget.fit,
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) {
      unawaited(
        ClientErrorReporter.reportGlobal(
          error,
          stackTrace ?? StackTrace.current,
          source: 'artifact.preview.image.decode',
        ),
      );
      return _PlaybackFailure(
        icon: LucideIcons.imageOff,
        retryKey: const Key('verified-image-retry'),
        onRetry: () => unawaited(_retry()),
      );
    },
  );
}

final class VerifiedArtifactVideo extends StatefulWidget {
  const VerifiedArtifactVideo({
    required this.media,
    this.errorSource = 'artifact.preview.video',
    this.autoplay = false,
    super.key,
  });

  final VerifiedArtifactMedia media;
  final String errorSource;
  final bool autoplay;

  @override
  State<VerifiedArtifactVideo> createState() => _VerifiedArtifactVideoState();
}

final class _VerifiedArtifactVideoState extends State<VerifiedArtifactVideo> {
  LocalVideoHandle? _handle;
  Object? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant VerifiedArtifactVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.identity.cacheKey != widget.media.identity.cacheKey) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _epoch++;
    final handle = _handle;
    _handle = null;
    if (handle != null) unawaited(handle.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _handle?.controller;
    if (_error != null) {
      return _PlaybackFailure(
        icon: LucideIcons.videoOff,
        retryKey: const Key('verified-video-retry'),
        onRetry: () => unawaited(_load()),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VideoProgressIndicator(controller, allowScrubbing: true),
        ),
        IconButton.filled(
          tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
          onPressed: () async {
            if (controller.value.isPlaying) {
              await controller.pause();
            } else {
              await controller.play();
            }
            if (mounted) setState(() {});
          },
          icon: Icon(
            controller.value.isPlaying ? LucideIcons.pause : LucideIcons.play,
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final previous = _handle;
    _handle = null;
    _error = null;
    if (mounted) setState(() {});
    if (previous != null) await previous.dispose();
    try {
      final next = await LocalVideoHandle.create(
        path: '',
        bytes: widget.media.bytes,
        contentType: widget.media.detectedContentType,
      );
      if (!mounted || epoch != _epoch) {
        await next.dispose();
        return;
      }
      _handle = next;
      if (widget.autoplay) await next.controller.play();
      if (mounted && epoch == _epoch) setState(() {});
    } on Object catch (error, stackTrace) {
      unawaited(
        ClientErrorReporter.reportGlobal(
          error,
          stackTrace,
          source: widget.errorSource,
        ),
      );
      if (mounted && epoch == _epoch) setState(() => _error = error);
    }
  }
}

final class VerifiedArtifactAudio extends StatelessWidget {
  const VerifiedArtifactAudio({
    required this.media,
    this.errorSource = 'artifact.preview.audio',
    super.key,
  });

  final VerifiedArtifactMedia media;
  final String errorSource;

  @override
  Widget build(BuildContext context) => AudioPlayerSurface.memory(
    key: ValueKey(media.identity.cacheKey),
    bytes: media.bytes,
    contentType: media.detectedContentType,
    errorSource: errorSource,
  );
}

final class _PlaybackFailure extends StatelessWidget {
  const _PlaybackFailure({
    required this.icon,
    required this.retryKey,
    required this.onRetry,
  });

  final IconData icon;
  final Key retryKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: IiOsColors.muted),
          IiOsGap.vXs,
          OutlinedButton.icon(
            key: retryKey,
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

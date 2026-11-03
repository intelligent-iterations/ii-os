import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:video_player/video_player.dart';

import '../services/local_video_handle.dart';

/// A small preview of an attached reference, so what was picked is visible
/// rather than described only by a filename.
///
/// Renders from bytes the draft already holds. Anything it cannot decode, and
/// any kind with nothing to show, falls back to [icon] -- the behaviour before
/// previews existed -- so a failure is never worse than the old row.
final class ReferenceMediaThumbnail extends StatelessWidget {
  const ReferenceMediaThumbnail({
    required this.bytes,
    required this.contentType,
    required this.icon,
    this.size = 44,
    super.key,
  });

  final Uint8List bytes;
  final String contentType;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final fallback = Center(child: Icon(icon, size: 18));
    final Widget content;
    if (bytes.isEmpty) {
      content = fallback;
    } else if (contentType.startsWith('image/')) {
      content = Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else if (contentType.startsWith('video/')) {
      content = _VideoFrameThumbnail(
        bytes: bytes,
        contentType: contentType,
        fallback: fallback,
      );
    } else {
      content = fallback;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// Shows a video's opening frame without controls or playback.
final class _VideoFrameThumbnail extends StatefulWidget {
  const _VideoFrameThumbnail({
    required this.bytes,
    required this.contentType,
    required this.fallback,
  });

  final Uint8List bytes;
  final String contentType;
  final Widget fallback;

  @override
  State<_VideoFrameThumbnail> createState() => _VideoFrameThumbnailState();
}

class _VideoFrameThumbnailState extends State<_VideoFrameThumbnail> {
  LocalVideoHandle? _handle;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _epoch += 1;
    unawaitedDispose(_handle);
    _handle = null;
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    try {
      final next = await LocalVideoHandle.create(
        path: '',
        bytes: widget.bytes,
        contentType: widget.contentType,
      );
      if (!mounted || epoch != _epoch) {
        await next.dispose();
        return;
      }
      setState(() => _handle = next);
    } on Object {
      // A thumbnail is not worth surfacing an error for; the icon stands in.
      if (mounted) setState(() => _handle = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    if (handle == null || !handle.controller.value.isInitialized) {
      return widget.fallback;
    }
    final size = handle.controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(handle.controller),
      ),
    );
  }
}

/// Disposes [handle] without awaiting, for use from [State.dispose].
void unawaitedDispose(LocalVideoHandle? handle) {
  handle?.dispose();
}

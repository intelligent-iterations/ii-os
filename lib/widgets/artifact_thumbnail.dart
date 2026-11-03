import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/client_error_reporter.dart';
import '../services/verified_artifact_media.dart';
import 'verified_artifact_playback.dart';

/// Loads the bytes behind one artifact preview.
typedef ArtifactPreviewLoader = Future<VerifiedArtifactMedia> Function();

/// One generated artifact, rendered as a picture.
///
/// Every grid of workspace media needs the same four states -- nothing to show,
/// fetching, failed, and the picture -- and each copy of them grew a different
/// spinner and a different silence on failure. [load] is supplied by the
/// caller, so this stays a widget over data and callbacks.
class ArtifactThumbnail extends StatefulWidget {
  const ArtifactThumbnail({
    required this.identity,
    required this.load,
    super.key,
    this.placeholderIcon = LucideIcons.image,
    this.semanticLabel,
    this.fit = BoxFit.cover,
    this.errorSource = 'artifact.thumbnail',
    this.overlay,
    this.decodeWidth = 720,
  });

  /// A change here refetches; an equal value does not, which is what keeps a
  /// rebuilt tile from re-downloading.
  final String identity;

  /// `null` when there is no preview to show -- audio, or a video generated
  /// before posters existed.
  final ArtifactPreviewLoader? load;

  final IconData placeholderIcon;
  final String? semanticLabel;
  final BoxFit fit;
  final String errorSource;

  /// Drawn over the picture once it loads. Only on success: a badge over a
  /// spinner claims something is there that may yet fail.
  final Widget? overlay;

  /// Decode width. A tile is a few hundred pixels wide, and the decoded
  /// bitmap -- not the bytes -- is what the image cache holds, so decoding
  /// posters at full resolution is how a picker gets slow and stays slow.
  final int? decodeWidth;

  @override
  State<ArtifactThumbnail> createState() => _ArtifactThumbnailState();
}

class _ArtifactThumbnailState extends State<ArtifactThumbnail> {
  Future<VerifiedArtifactMedia>? _media;

  @override
  void initState() {
    super.initState();
    _media = widget.load?.call();
  }

  @override
  void didUpdateWidget(covariant ArtifactThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity ||
        (widget.load == null) != (oldWidget.load == null)) {
      _restart();
    }
  }

  /// The future is created before `setState`, not inside it: a callback that
  /// returns one is an error, and an easy shape to reach for here.
  void _restart() {
    final next = widget.load?.call();
    if (!mounted) return;
    setState(() => _media = next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final future = _media;
    if (future == null) {
      return IiOsMediaWell(
        child: Icon(
          widget.placeholderIcon,
          size: IiOsIconSize.xxl,
          color: palette.muted,
          semanticLabel: widget.semanticLabel,
        ),
      );
    }
    return FutureBuilder<VerifiedArtifactMedia>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const IiOsMediaWell(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final media = snapshot.data;
        if (snapshot.hasError || media == null) {
          if (snapshot.error case final Object error) {
            unawaited(
              ClientErrorReporter.reportGlobal(
                error,
                snapshot.stackTrace ?? StackTrace.current,
                source: widget.errorSource,
              ),
            );
          }
          return IiOsMediaWell(
            child: IconButton(
              tooltip: 'Preview unavailable \u2014 try again',
              onPressed: _restart,
              icon: Icon(
                LucideIcons.rotateCw,
                size: IiOsIconSize.lg,
                color: palette.muted,
              ),
            ),
          );
        }
        final image = VerifiedArtifactImage(
          media: media,
          fit: widget.fit,
          cacheWidth: widget.decodeWidth,
        );
        final overlay = widget.overlay;
        if (overlay == null) return image;
        return Stack(fit: StackFit.expand, children: [image, overlay]);
      },
    );
  }
}

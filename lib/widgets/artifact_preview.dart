import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/verified_artifact_media.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';
import 'verified_artifact_playback.dart';

class ArtifactPreviewAction extends StatefulWidget {
  const ArtifactPreviewAction({
    required this.load,
    this.autoplay = false,
    this.presentation = ArtifactPreviewPresentation.eye,
    super.key,
  });

  final Future<VerifiedArtifactMedia> Function() load;
  final bool autoplay;
  final ArtifactPreviewPresentation presentation;

  @override
  State<ArtifactPreviewAction> createState() => _ArtifactPreviewActionState();
}

class _ArtifactPreviewActionState extends State<ArtifactPreviewAction> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (widget.presentation == ArtifactPreviewPresentation.play) {
      return Center(
        child: IconButton.filled(
          key: const Key('history-video-play'),
          tooltip: 'Play video',
          onPressed: _loading ? null : _open,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.play, size: 22),
        ),
      );
    }
    return IconButton(
      tooltip: 'Preview asset',
      onPressed: _loading ? null : _open,
      icon: _loading
          ? const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.eye, size: 18),
    );
  }

  Future<void> _open() async {
    setState(() => _loading = true);
    try {
      final media = await widget.load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ArtifactPreviewDialog(
          media: media,
          autoplay: widget.autoplay,
        ),
      );
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

enum ArtifactPreviewPresentation { eye, play }

class _ArtifactPreviewDialog extends StatelessWidget {
  const _ArtifactPreviewDialog({required this.media, required this.autoplay});

  final VerifiedArtifactMedia media;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    final contentType = media.detectedContentType;
    return Dialog(
      insetPadding: const EdgeInsets.all(IiOsSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      media.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 19),
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: ColoredBox(
                color: contentType.startsWith('audio/')
                    ? IiOsColors.canvas
                    : Colors.black,
                child: contentType.startsWith('video/')
                    ? VerifiedArtifactVideo(media: media, autoplay: autoplay)
                    : contentType.startsWith('audio/')
                    ? VerifiedArtifactAudio(
                        media: media,
                        errorSource: 'artifact.preview.audio.local',
                      )
                    : InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: VerifiedArtifactImage(media: media),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

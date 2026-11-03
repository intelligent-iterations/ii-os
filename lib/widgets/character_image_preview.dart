import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../services/client_error_reporter.dart';
import '../services/verified_artifact_media.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'verified_artifact_playback.dart';

Future<void> showCharacterImagePreview(
  BuildContext context,
  AppController controller,
  CharacterImageModel image,
) => showDialog<void>(
  context: context,
  builder: (context) =>
      _CharacterImagePreviewDialog(controller: controller, image: image),
);

class _CharacterImagePreviewDialog extends StatelessWidget {
  const _CharacterImagePreviewDialog({
    required this.controller,
    required this.image,
  });

  final AppController controller;
  final CharacterImageModel image;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey('character-image-preview-dialog'),
      insetPadding: const EdgeInsets.all(IiOsSpacing.md),
      child: SizedBox(
        width: math.min(1400.0, viewport.width * 0.94),
        height: math.min(1000.0, viewport.height * 0.9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      image.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close full-size image',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  key: const ValueKey('character-image-preview-zoom'),
                  minScale: 0.5,
                  maxScale: 6,
                  boundaryMargin: const EdgeInsets.all(IiOsSpacing.xxxl),
                  child: CharacterVerifiedImage(
                    controller: controller,
                    image: image,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CharacterVerifiedImage extends StatefulWidget {
  const CharacterVerifiedImage({
    required this.controller,
    required this.image,
    this.fit = BoxFit.contain,
    super.key,
  });

  final AppController controller;
  final CharacterImageModel image;
  final BoxFit fit;

  @override
  State<CharacterVerifiedImage> createState() => _CharacterVerifiedImageState();
}

class _CharacterVerifiedImageState extends State<CharacterVerifiedImage> {
  Future<VerifiedArtifactMedia>? _media;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant CharacterVerifiedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.image.cacheKey != widget.image.cacheKey ||
        oldWidget.image.readUrl != widget.image.readUrl) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.image.hasReadGrant) {
      return CharacterImageLoadFailure(message: widget.image.urlErrorMessage);
    }
    return FutureBuilder<VerifiedArtifactMedia>(
      future: _media,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const CharacterImageLoadFailure(
            message: 'The sheet could not be verified. Refresh and try again.',
          );
        }
        final media = snapshot.data;
        if (media == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return VerifiedArtifactImage(media: media, fit: widget.fit);
      },
    );
  }

  void _refresh() {
    _media = widget.image.hasReadGrant ? _load() : null;
  }

  Future<VerifiedArtifactMedia> _load() async {
    try {
      return await widget.controller.readCharacterImage(widget.image);
    } on Object catch (error, stackTrace) {
      unawaited(
        ClientErrorReporter.reportGlobal(
          error,
          stackTrace,
          source: 'character.image.verified',
        ),
      );
      rethrow;
    }
  }
}

class CharacterImageLoadFailure extends StatelessWidget {
  const CharacterImageLoadFailure({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 96 || constraints.maxHeight < 96;
      final detail = message?.trim();
      final icon = const Icon(LucideIcons.imageOff, color: IiOsColors.muted);
      return ColoredBox(
        color: IiOsColors.canvas,
        child: Center(
          child: compact
              ? Tooltip(
                  message: detail?.isNotEmpty == true
                      ? detail!
                      : 'Image unavailable',
                  child: icon,
                )
              : Padding(
                  padding: const EdgeInsets.all(IiOsSpacing.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon,
                      if (detail?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(
                          detail!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      );
    },
  );
}

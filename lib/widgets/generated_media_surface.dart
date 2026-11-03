import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show MediaDownloadButton;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/generated_media.dart';
import '../screens/playground_ghost_cleanup_overlay.dart';
import '../services/verified_artifact_media.dart';
import '../services/verified_artifact_file_saver.dart';
import '../state/app_controller.dart';
import '../state/app_controller_ghost.dart';
import '../state/generated_artifact_session.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'verified_artifact_playback.dart';

export '../models/generated_media.dart';

class GeneratedMediaSurface extends StatelessWidget {
  const GeneratedMediaSurface({
    required this.controller,
    required this.job,
    required this.kind,
    this.aspectRatio,
    this.mediaLabel,
    super.key,
  });

  final AppController controller;
  final JsonMap job;
  final GeneratedMediaKind kind;
  final double? aspectRatio;
  final String? mediaLabel;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String? ?? 'requested';
    final artifact = generatedMediaArtifact(job, kind);
    final jobId = job['jobId'] as String? ?? '';
    final workspaceId = controller.workspace?.id ?? '';
    final ratio = aspectRatio ?? _defaultAspectRatio(kind);
    return _GeneratedMediaFrame(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(IiOsRadii.md),
        child: ColoredBox(
          color: _surfaceColor(kind),
          child: artifact != null && jobId.isNotEmpty && workspaceId.isNotEmpty
              ? _GeneratedArtifact(
                  controller: controller,
                  workspaceId: workspaceId,
                  jobId: jobId,
                  artifact: artifact,
                  kind: kind,
                  ghostMode: job['ghostMode'] == true,
                )
              : _GeneratedMediaState(
                  kind: kind,
                  status: status,
                  mediaLabel: mediaLabel,
                ),
        ),
      ),
    );
  }
}

class GeneratedMediaLoadingSurface extends StatelessWidget {
  const GeneratedMediaLoadingSurface({
    required this.kind,
    this.aspectRatio,
    this.label,
    this.mediaLabel,
    super.key,
  });

  final GeneratedMediaKind kind;
  final double? aspectRatio;
  final String? label;
  final String? mediaLabel;

  @override
  Widget build(BuildContext context) => _GeneratedMediaFrame(
    aspectRatio: aspectRatio ?? _defaultAspectRatio(kind),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(IiOsRadii.md),
      child: ColoredBox(
        color: _surfaceColor(kind),
        child: _GeneratedMediaState(
          kind: kind,
          status: 'requested',
          activeLabel: label,
          mediaLabel: mediaLabel,
        ),
      ),
    ),
  );
}

class _GeneratedMediaFrame extends StatelessWidget {
  const _GeneratedMediaFrame({required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height * .55).clamp(
      220.0,
      620.0,
    );
    return Align(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxHeight * aspectRatio,
          maxHeight: maxHeight,
        ),
        child: AspectRatio(aspectRatio: aspectRatio, child: child),
      ),
    );
  }
}

class _GeneratedMediaState extends StatelessWidget {
  const _GeneratedMediaState({
    required this.kind,
    required this.status,
    this.activeLabel,
    this.mediaLabel,
  });

  final GeneratedMediaKind kind;
  final String status;
  final String? activeLabel;
  final String? mediaLabel;

  @override
  Widget build(BuildContext context) {
    final label = _mediaLabel(kind, customLabel: mediaLabel);
    final foreground = kind == GeneratedMediaKind.video
        ? Colors.white
        : IiOsColors.charcoal;
    if (generatedMediaJobIsActive(status)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2, color: foreground),
            IiOsGap.vSm,
            Text(
              activeLabel ?? 'Generating $label\u2026',
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    final failed = status == 'failed' || status == 'cancelled';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? LucideIcons.circleAlert : _emptyIcon(kind),
              color: failed ? IiOsColors.red : IiOsColors.muted,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              failed
                  ? '${_sentenceCase(status)} before a $label was produced.'
                  : 'The completed job did not attach a $label.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kind == GeneratedMediaKind.video
                    ? Colors.white
                    : IiOsColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratedArtifact extends StatefulWidget {
  const _GeneratedArtifact({
    required this.controller,
    required this.workspaceId,
    required this.jobId,
    required this.artifact,
    required this.kind,
    required this.ghostMode,
  });

  final AppController controller;
  final String workspaceId;
  final String jobId;
  final JsonMap artifact;
  final GeneratedMediaKind kind;
  final bool ghostMode;

  @override
  State<_GeneratedArtifact> createState() => _GeneratedArtifactState();
}

class _GeneratedArtifactState extends State<_GeneratedArtifact> {
  late GeneratedArtifactSession _session;

  @override
  void initState() {
    super.initState();
    _session = _newSession()..addListener(_changed);
  }

  @override
  void didUpdateWidget(_GeneratedArtifact oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.ghostMode != widget.ghostMode ||
        oldWidget.artifact['path'] != widget.artifact['path'] ||
        oldWidget.artifact['generation'] != widget.artifact['generation']) {
      _session
        ..removeListener(_changed)
        ..dispose();
      _session = _newSession()..addListener(_changed);
    }
  }

  GeneratedArtifactSession _newSession() => GeneratedArtifactSession(
    ghostMode: widget.ghostMode,
    load: () => widget.controller.readVerifiedArtifact(
      workspaceId: widget.workspaceId,
      jobId: widget.jobId,
      artifact: widget.artifact,
      transient: widget.ghostMode,
    ),
    consume: () => widget.controller.consumeGhostJob(widget.jobId),
  );

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _save(VerifiedArtifactMedia media) async {
    try {
      await saveVerifiedArtifactMedia(
        media: media,
        fallbackName: 'ii-os-ghost-${widget.kind.name}-${widget.jobId}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved a local copy.')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The local copy could not be saved. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VerifiedArtifactMedia>(
    future: _session.media,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      final media = snapshot.data;
      if (snapshot.hasError || media == null) {
        return _GeneratedArtifactFailure(
          kind: widget.kind,
          onRetry: _session.reload,
        );
      }
      final content = switch (widget.kind) {
        GeneratedMediaKind.video => VerifiedArtifactVideo(
          media: media,
          errorSource: 'generated.video.player.local',
        ),
        GeneratedMediaKind.audio => VerifiedArtifactAudio(
          media: media,
          errorSource: 'generated.audio.player.local',
        ),
        GeneratedMediaKind.image => VerifiedArtifactImage(media: media),
      };
      final presented = _session.cleanupError == null
          ? content
          : PlaygroundGhostCleanupOverlay(
              content: content,
              cleaning: _session.cleaning,
              onRetry: _session.retryCleanup,
            );
      if (!widget.ghostMode) return presented;
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: presented),
          Positioned(
            top: IiOsSpacing.sm,
            right: IiOsSpacing.sm,
            child: MediaDownloadButton(onPressed: () => _save(media)),
          ),
        ],
      );
    },
  );
}

class _GeneratedArtifactFailure extends StatelessWidget {
  const _GeneratedArtifactFailure({required this.kind, required this.onRetry});

  final GeneratedMediaKind kind;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_emptyIcon(kind), color: IiOsColors.muted),
          IiOsGap.vXs,
          Text(
            'This media could not be verified.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kind == GeneratedMediaKind.video
                  ? Colors.white
                  : IiOsColors.muted,
            ),
          ),
          IiOsGap.vXs,
          FilledButton.icon(
            key: const Key('generated-media-retry'),
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

double _defaultAspectRatio(GeneratedMediaKind kind) => switch (kind) {
  GeneratedMediaKind.image => 1,
  GeneratedMediaKind.video => 16 / 9,
  GeneratedMediaKind.audio => 3,
};

Color _surfaceColor(GeneratedMediaKind kind) => switch (kind) {
  GeneratedMediaKind.video => Colors.black,
  GeneratedMediaKind.image || GeneratedMediaKind.audio => IiOsColors.canvas,
};

String _mediaLabel(GeneratedMediaKind kind, {String? customLabel}) {
  final normalized = customLabel?.trim();
  if (kind == GeneratedMediaKind.audio &&
      normalized != null &&
      normalized.isNotEmpty) {
    return normalized;
  }
  return switch (kind) {
    GeneratedMediaKind.image => 'image',
    GeneratedMediaKind.video => 'video',
    GeneratedMediaKind.audio => 'song',
  };
}

IconData _emptyIcon(GeneratedMediaKind kind) => switch (kind) {
  GeneratedMediaKind.image => LucideIcons.imageOff,
  GeneratedMediaKind.video => LucideIcons.videoOff,
  GeneratedMediaKind.audio => LucideIcons.audioLines,
};

String _sentenceCase(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';

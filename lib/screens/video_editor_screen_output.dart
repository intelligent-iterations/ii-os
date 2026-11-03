part of 'video_editor_screen.dart';

extension _VideoEditorOutput on _VideoEditorScreenState {
  Widget _outputSurface(EditorProject project, MediaTime playhead) {
    if (_phase == _OutputPhase.rendering || _phase == _OutputPhase.uploading) {
      return VideoEditorProgressSurface(
        stage: _stage,
        progress: _progress,
        onCancel: _phase == _OutputPhase.rendering ? _cancelRender : null,
      );
    }
    final artifact = _artifact;
    if (_phase == _OutputPhase.failed) {
      final healingDraft = buildVideoEditorExportHealingDraft(
        workspace: widget.controller.workspace,
        error: _outputError ?? 'The local export failed.',
        sourceContentTypes: _media.values.map((media) => media.contentType),
        duration: Duration(microseconds: project.duration.microseconds),
      );
      final canCreateTicket =
          widget.controller.can('tickets.write') && healingDraft != null;
      final ticketDisabledReason = canCreateTicket
          ? null
          : widget.controller.can('tickets.write')
          ? 'Configure a Software Workshop room before creating a healing ticket.'
          : 'Ask a workspace editor to create a Software Workshop ticket.';
      return ColoredBox(
        key: const ValueKey('video-editor-output-surface'),
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (artifact != null)
              LocalEditorExportPreview(artifact: artifact)
            else
              const SizedBox.expand(),
            Center(
              child: Card(
                child: SizedBox(
                  width: 460,
                  child: ErrorSurface(
                    title: 'Export did not finish',
                    message: _outputError ?? 'The local export failed.',
                    onRetry: _renderedBytes == null ? _render : _uploadRendered,
                    retryLabel: _renderedBytes == null
                        ? 'Retry local render'
                        : 'Retry direct upload',
                    secondaryActions: [
                      if (_renderedBytes != null)
                        OutlinedButton.icon(
                          onPressed: _savingCopy ? null : _saveRendered,
                          icon: _savingCopy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Save local copy'),
                        ),
                      OutlinedButton.icon(
                        onPressed: canCreateTicket
                            ? () => _openHealingTicket(healingDraft)
                            : null,
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Create healing ticket'),
                      ),
                    ],
                    disabledReason: ticketDisabledReason,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (artifact != null) {
      return KeyedSubtree(
        key: const ValueKey('video-editor-output-surface'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LocalEditorExportPreview(artifact: artifact),
            Positioned(
              right: 12,
              top: 12,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (!widget.ghostMode && artifact.assetId != null) ...[
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _openInH3(MiniMaxH3GenerationMode.videoContinue),
                      icon: const Icon(LucideIcons.fastForward, size: 17),
                      label: const Text('Continue with H3'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _openInH3(MiniMaxH3GenerationMode.videoEdit),
                      icon: const Icon(LucideIcons.sparkles, size: 17),
                      label: const Text('Transform with H3'),
                    ),
                  ],
                  FilledButton.tonalIcon(
                    onPressed: _savingCopy ? null : _saveRendered,
                    icon: _savingCopy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Save local copy'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return KeyedSubtree(
      key: const ValueKey('video-editor-output-surface'),
      child: _sourcePreview(project, playhead),
    );
  }

  void _openHealingTicket(WorkshopTicketDraft draft) {
    widget.controller.workshopTicketDrafts.stage(draft);
    context.go(
      AppRouteState(
        workspaceId: draft.workspaceId,
        page: AppPage.tickets,
        itemId: draft.roomId,
        query: {'repository': draft.repository, 'project': draft.projectId},
      ).location,
    );
  }

  Widget _sourcePreview(EditorProject project, MediaTime playhead) {
    final clips = activeVideoClips(project, playhead).toList();
    final captions = activeCaptionClips(project, playhead).toList();
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: _editorCanvasColor(project.backgroundColor)),
          for (final clip in clips)
            Positioned(
              key: ValueKey('video-editor-visual-${clip.id}'),
              left: constraints.maxWidth * clip.destination.x,
              top: constraints.maxHeight * clip.destination.y,
              width: constraints.maxWidth * clip.destination.width,
              height: constraints.maxHeight * clip.destination.height,
              child: Opacity(
                opacity: clip.opacity,
                child: _visualLayerPreview(
                  clip,
                  playhead,
                  showControls: clips.length == 1,
                ),
              ),
            ),
          if (clips.isEmpty)
            const Center(
              child: Text(
                'No video at this playhead',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          for (final caption in captions)
            Positioned(
              left: constraints.maxWidth * caption.destination.x,
              top: constraints.maxHeight * caption.destination.y,
              width: constraints.maxWidth * caption.destination.width,
              height: constraints.maxHeight * caption.destination.height,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(caption.style.backgroundColor),
                    borderRadius: BorderRadius.circular(
                      caption.style.cornerRadius,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: caption.style.horizontalPadding,
                      vertical: caption.style.verticalPadding,
                    ),
                    child: Text(
                      caption.text,
                      maxLines: caption.style.maxLines,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(caption.style.textColor),
                        fontSize: caption.style.fontSize,
                        fontWeight: FontWeight
                            .values[(caption.style.fontWeight ~/ 100) - 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _visualLayerPreview(
    EditorVideoClip clip,
    MediaTime playhead, {
    required bool showControls,
  }) {
    final media = _media[clip.source.id];
    final sourcePosition = Duration(
      microseconds:
          clip.sourceRange.start.microseconds +
          playhead.microseconds -
          clip.timelineStart.microseconds,
    );
    final fit = switch (clip.fit) {
      MediaFit.contain => BoxFit.contain,
      MediaFit.cover => BoxFit.cover,
      MediaFit.fill => BoxFit.fill,
    };
    if (media?.contentType.startsWith('image/') ?? false) {
      return Image.memory(
        media!.bytes,
        key: ValueKey('video-editor-image-${clip.id}'),
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white70),
        ),
      );
    }
    return LocalVideoPreview(
      media: media,
      sourcePosition: sourcePosition,
      backgroundColor: Colors.transparent,
      fit: fit,
      showControls: showControls,
    );
  }

  Color _editorCanvasColor(String value) {
    final rgb = int.tryParse(value, radix: 16);
    return rgb == null ? Colors.black : Color(0xff000000 | rgb);
  }
}

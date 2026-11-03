import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'character_image_preview.dart';

class CharacterSelectedSheet extends StatelessWidget {
  const CharacterSelectedSheet({
    this.image,
    this.controller,
    this.generationStatus,
    this.generationJobId,
    this.errorCode,
    this.onRetry,
    this.onTweakSheet,
    this.onEditArea,
    super.key,
  });

  final CharacterImageModel? image;
  final AppController? controller;
  final String? generationStatus;
  final String? generationJobId;
  final String? errorCode;
  final VoidCallback? onRetry;
  final VoidCallback? onTweakSheet;
  final VoidCallback? onEditArea;

  @override
  Widget build(BuildContext context) {
    if (_activeGenerationStatuses.contains(generationStatus)) {
      return const _GenerationPlaceholder(active: true);
    }
    if (generationStatus == 'completed' &&
        generationJobId?.isNotEmpty == true &&
        image?.jobId != generationJobId) {
      return const _GenerationPlaceholder(
        active: true,
        activeLabel: 'Preparing generated character sheet\u2026',
      );
    }
    if (image == null) {
      if (generationStatus == 'completed') {
        return const _GenerationPlaceholder(
          active: true,
          activeLabel: 'Preparing generated character sheet\u2026',
        );
      }
      if (_terminalGenerationStatuses.contains(generationStatus)) {
        return _GenerationPlaceholder(
          active: false,
          errorCode: errorCode,
          onRetry: onRetry,
        );
      }
      return const SizedBox.shrink(
        key: ValueKey('character-selected-sheet-empty'),
      );
    }
    final maxHeight = (MediaQuery.sizeOf(context).height * .4).clamp(
      0.0,
      360.0,
    );
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 980, maxHeight: maxHeight),
        child: ClipRRect(
          key: const ValueKey('character-selected-sheet'),
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _SelectedSheetImage(
                        controller: controller,
                        image: image!,
                      ),
                      if (onTweakSheet != null || onEditArea != null)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              if (onTweakSheet != null)
                                FilledButton.tonalIcon(
                                  key: const ValueKey(
                                    'character-tweak-sheet-open',
                                  ),
                                  onPressed: onTweakSheet,
                                  icon: const Icon(
                                    LucideIcons.slidersHorizontal,
                                    size: 16,
                                  ),
                                  label: const Text('Tweak entire sheet'),
                                ),
                              if (onEditArea != null)
                                FilledButton.tonalIcon(
                                  key: const ValueKey(
                                    'character-edit-area-open',
                                  ),
                                  onPressed: onEditArea,
                                  icon: const Icon(LucideIcons.scan, size: 16),
                                  label: const Text('Edit an area'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenerationPlaceholder extends StatelessWidget {
  const _GenerationPlaceholder({
    required this.active,
    this.activeLabel,
    this.errorCode,
    this.onRetry,
  });

  final bool active;
  final String? activeLabel;
  final String? errorCode;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(
      active
          ? 'character-selected-sheet-generating'
          : 'character-selected-sheet-failed',
    ),
    constraints: const BoxConstraints(minHeight: 220),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: IiOsColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              const CircularProgressIndicator(strokeWidth: 2)
            else
              const Icon(
                LucideIcons.circleAlert,
                color: IiOsColors.red,
                size: 28,
              ),
            IiOsGap.vSm,
            Text(
              active
                  ? activeLabel ?? 'Generating character sheet\u2026'
                  : 'Character sheet generation failed',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (!active) ...[
              const SizedBox(height: 6),
              Text(
                errorCode == null || errorCode!.isEmpty
                    ? 'No image was produced.'
                    : 'No image was produced ($errorCode).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (onRetry != null) ...[
                IiOsGap.vSm,
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Retry generation'),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

class _SelectedSheetImage extends StatelessWidget {
  const _SelectedSheetImage({required this.controller, required this.image});

  final AppController? controller;
  final CharacterImageModel image;

  @override
  Widget build(BuildContext context) {
    final appController = controller;
    if (appController == null) {
      return const Center(
        child: Icon(LucideIcons.imageOff, color: IiOsColors.muted),
      );
    }
    return CharacterVerifiedImage(
      key: ValueKey('selected-sheet-${image.path}'),
      controller: appController,
      image: image,
    );
  }
}

const _activeGenerationStatuses = {
  'dispatching',
  'dispatched',
  'queued',
  'requested',
  'running',
  'in_progress',
  'pending',
  'cancelling',
};

const _terminalGenerationStatuses = {'failed', 'cancelled'};

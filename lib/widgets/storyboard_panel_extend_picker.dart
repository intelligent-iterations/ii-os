import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'storyboard_editor_components.dart';

final class StoryboardExtendOption {
  const StoryboardExtendOption({
    required this.panelId,
    required this.name,
    required this.thumbnail,
  });

  final String panelId;
  final String name;
  final Widget thumbnail;
}

List<StoryboardExtendOption> storyboardPanelExtendOptions({
  required List<StoryboardPanelDraft> panels,
  required String currentPanelId,
  required AppController controller,
  required String workspaceId,
}) => [
  for (final (index, panel) in panels.indexed)
    if (panel.id != currentPanelId)
      if (panel.videoArtifact case final artifact?)
        if (panel.videoJobId case final jobId?)
          StoryboardExtendOption(
            panelId: panel.id,
            name: 'Panel ${index + 1}',
            thumbnail: ClipRRect(
              borderRadius: BorderRadius.circular(IiOsRadii.sm),
              child: SizedBox.square(
                dimension: 32,
                child: panel.imageArtifact != null && panel.imageJobId != null
                    ? StoryboardArtifactImage(
                        key: ValueKey(
                          'storyboard-extend-thumbnail-${panel.id}-$jobId-'
                          '${artifact['path']}-${artifact['generation']}',
                        ),
                        controller: controller,
                        workspaceId: workspaceId,
                        jobId: panel.imageJobId!,
                        artifact: panel.imageArtifact!,
                      )
                    : const ColoredBox(
                        color: IiOsColors.surface,
                        child: Icon(LucideIcons.clapperboard, size: 16),
                      ),
              ),
            ),
          ),
];

class StoryboardPanelExtendPicker extends StatelessWidget {
  const StoryboardPanelExtendPicker({
    required this.options,
    required this.extendedFromPanelId,
    required this.extending,
    required this.enabled,
    required this.onExtend,
    super.key,
  });

  final List<StoryboardExtendOption> options;
  final String? extendedFromPanelId;
  final bool extending;
  final bool enabled;
  final ValueChanged<String> onExtend;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final extendedFromName = extendedFromPanelId == null
        ? null
        : options
              .cast<StoryboardExtendOption?>()
              .firstWhere(
                (option) => option?.panelId == extendedFromPanelId,
                orElse: () => null,
              )
              ?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Extend from panel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (extending)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          extendedFromName != null
              ? 'This panel continues from $extendedFromName\'s last frame.'
              : 'Continue a panel with a generated video from its last frame '
                    'instead of generating a new image.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                key: ValueKey('storyboard-extend-option-${option.panelId}'),
                label: Text(option.name),
                avatar: option.thumbnail,
                selected: option.panelId == extendedFromPanelId,
                onSelected: enabled && !extending
                    ? (_) => onExtend(option.panelId)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

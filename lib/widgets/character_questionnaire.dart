import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';

enum CharacterViewTab { head, body }

class CharacterViewTabs extends StatelessWidget {
  const CharacterViewTabs({
    required this.selected,
    required this.onSelected,
    this.headReady = false,
    this.bodyReady = false,
    super.key,
  });

  final CharacterViewTab selected;
  final ValueChanged<CharacterViewTab> onSelected;
  final bool headReady;
  final bool bodyReady;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Build one final full-body reference sheet'),
            IiOsGap.vXxs,
            Text(
              'Finish and select one close-up head sheet and one full-body sheet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final head = _OutputChoice(
                  step: 'Output 1 of 2',
                  title: 'Head',
                  description: 'Close-up identity sheet',
                  icon: LucideIcons.scanFace,
                  selected: selected == CharacterViewTab.head,
                  ready: headReady,
                  onTap: () => onSelected(CharacterViewTab.head),
                );
                final body = _OutputChoice(
                  step: 'Output 2 of 2',
                  title: 'Body',
                  description: 'Full-body form and outfit sheet',
                  icon: LucideIcons.personStanding,
                  selected: selected == CharacterViewTab.body,
                  ready: bodyReady,
                  onTap: () => onSelected(CharacterViewTab.body),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [head, const SizedBox(height: 10), body],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: head),
                    const SizedBox(width: 10),
                    Expanded(child: body),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OutputChoice extends StatelessWidget {
  const _OutputChoice({
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.ready,
    required this.onTap,
  });

  final String step;
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? IiOsColors.green : IiOsColors.border;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$step, $title, ${ready ? 'selected output ready' : 'not selected yet'}',
      child: Material(
        color: selected ? IiOsColors.greenTint : IiOsColors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: color, width: selected ? 2 : 1),
        ),
        child: InkWell(
          key: ValueKey('character-output-${title.toLowerCase()}'),
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? IiOsColors.green.withValues(alpha: 0.13)
                        : IiOsColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    ready ? LucideIcons.circleCheck : icon,
                    color: ready || selected
                        ? IiOsColors.green
                        : IiOsColors.muted,
                  ),
                ),
                IiOsGap.hSm,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 1),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (ready)
                  const Padding(
                    padding: EdgeInsets.only(left: IiOsSpacing.xs),
                    child: Text(
                      'Selected',
                      style: TextStyle(
                        color: IiOsColors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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

class CharacterPromptPreview extends StatelessWidget {
  const CharacterPromptPreview({
    this.title = 'Z-Image prompt',
    required this.prompt,
    required this.saving,
    required this.dirty,
    required this.error,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String prompt;
  final bool saving;
  final bool dirty;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = error != null
        ? 'Save failed'
        : saving
        ? 'Saving\u2026'
        : dirty
        ? 'Unsaved changes'
        : 'Saved';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              title,
              trailing: IconButton(
                tooltip: 'Copy prompt',
                onPressed: prompt.isEmpty
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: prompt)),
                icon: const Icon(LucideIcons.copy, size: 17),
              ),
            ),
            IiOsGap.vXxs,
            Row(
              children: [
                Icon(
                  error != null ? LucideIcons.triangleAlert : LucideIcons.save,
                  size: 14,
                  color: error != null ? IiOsColors.red : IiOsColors.muted,
                ),
                const SizedBox(width: 6),
                Text(status, style: Theme.of(context).textTheme.bodySmall),
                if (error != null) ...[
                  const Spacer(),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
            IiOsGap.vSm,
            Container(
              constraints: const BoxConstraints(maxHeight: 680),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: IiOsColors.canvas,
                border: Border.all(color: IiOsColors.border),
                borderRadius: BorderRadius.circular(5),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  prompt,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.45,
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

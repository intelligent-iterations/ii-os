import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class CharacterDetailFooter extends StatelessWidget {
  const CharacterDetailFooter({
    required this.canSave,
    required this.canGenerate,
    required this.saving,
    required this.generating,
    required this.generateLabel,
    required this.onSave,
    required this.onGenerate,
    super.key,
  });

  final bool canSave;
  final bool canGenerate;
  final bool saving;
  final bool generating;
  final String generateLabel;
  final Future<bool> Function() onSave;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        return Material(
          elevation: 8,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(IiOsRadii.pill),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: IiOsColors.border),
              borderRadius: BorderRadius.circular(IiOsRadii.pill),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(IiOsSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: canSave ? () => unawaited(onSave()) : null,
                    icon: saving
                        ? const CharacterProgressIcon()
                        : const Icon(LucideIcons.save, size: 17),
                    label: const Text('Save'),
                  ),
                  IiOsGap.hXs,
                  FilledButton.icon(
                    onPressed: canGenerate ? onGenerate : null,
                    icon: generating
                        ? const CharacterProgressIcon()
                        : const Icon(LucideIcons.sparkles, size: 17),
                    label: Text(compact ? 'Generate' : generateLabel),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class CharacterProgressIcon extends StatelessWidget {
  const CharacterProgressIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

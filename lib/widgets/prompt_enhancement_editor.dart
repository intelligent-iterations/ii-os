import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'common.dart';

/// Pasted into ii-os, or named as a Secret Manager version the customer keeps.
enum PromptEnhancementKeySource { pasted, secretManager }

/// The DeepSeek credential and switch for explicit Enhance buttons.
class PromptEnhancementEditor extends StatelessWidget {
  const PromptEnhancementEditor({
    required this.enabled,
    required this.keySource,
    required this.secretVersionController,
    required this.apiKeyController,
    required this.installedKeyLast4,
    required this.onEnabledChanged,
    required this.onKeySourceChanged,
    required this.onRemoveKey,
    super.key,
  });

  final bool enabled;
  final PromptEnhancementKeySource keySource;
  final TextEditingController secretVersionController;
  final TextEditingController apiKeyController;

  /// The last four characters of the key already stored, or empty.
  final String installedKeyLast4;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<PromptEnhancementKeySource> onKeySourceChanged;
  final VoidCallback? onRemoveKey;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Prompt enhancement'),
            IiOsGap.vXs,
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Enhance buttons'),
              subtitle: const Text(
                'Rewrites a field only when someone presses Enhance. '
                'Generation never rewrites prompts automatically. The field '
                'text and attached-image count go to DeepSeek; images do not.',
              ),
              value: enabled,
              onChanged: onEnabledChanged,
            ),
            IiOsGap.vSm,
            SegmentedButton<PromptEnhancementKeySource>(
              segments: const [
                ButtonSegment(
                  value: PromptEnhancementKeySource.pasted,
                  icon: Icon(LucideIcons.keyRound, size: IiOsIconSize.sm),
                  label: Text('Paste a key'),
                ),
                ButtonSegment(
                  value: PromptEnhancementKeySource.secretManager,
                  icon: Icon(LucideIcons.cloudCog, size: IiOsIconSize.sm),
                  label: Text('Secret Manager'),
                ),
              ],
              selected: {keySource},
              onSelectionChanged: (s) => onKeySourceChanged(s.first),
            ),
            IiOsGap.vSm,
            if (keySource == PromptEnhancementKeySource.secretManager)
              TextField(
                controller: secretVersionController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'DeepSeek API key secret version',
                  hintText: 'projects/my-project/secrets/key/versions/latest',
                  helperText: 'Grant the ii-os service account access.',
                  helperMaxLines: 3,
                  prefixIcon: Icon(LucideIcons.cloudCog, size: IiOsIconSize.md),
                ),
              )
            else
              _PastedKeyField(
                controller: apiKeyController,
                installedKeyLast4: installedKeyLast4,
                onRemoveKey: onRemoveKey,
              ),
          ],
        ),
      ),
    );
  }
}

class _PastedKeyField extends StatelessWidget {
  const _PastedKeyField({
    required this.controller,
    required this.installedKeyLast4,
    required this.onRemoveKey,
  });

  final TextEditingController controller;
  final String installedKeyLast4;
  final VoidCallback? onRemoveKey;

  @override
  Widget build(BuildContext context) {
    final installed = installedKeyLast4.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: true,
          decoration: InputDecoration(
            labelText: installed
                ? 'Replace the DeepSeek API key'
                : 'DeepSeek API key',
            // Never sent back, so an empty box must not read as "no key".
            helperText: installed
                ? 'A key ending ····$installedKeyLast4 is installed. Leave '
                      'this empty to keep it.'
                : 'Stored encrypted. ii-os never shows it again after saving.',
            helperMaxLines: 3,
            prefixIcon: const Icon(LucideIcons.keyRound, size: IiOsIconSize.md),
          ),
        ),
        if (installed && onRemoveKey != null) ...[
          IiOsGap.vXs,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRemoveKey,
              icon: const Icon(LucideIcons.trash2, size: IiOsIconSize.sm),
              label: const Text('Remove stored key'),
            ),
          ),
        ],
      ],
    );
  }
}

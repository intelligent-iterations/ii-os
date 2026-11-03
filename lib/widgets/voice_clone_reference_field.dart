import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class VoiceCloneReferenceField extends StatelessWidget {
  const VoiceCloneReferenceField({
    required this.enabled,
    required this.useVoiceClone,
    required this.consent,
    required this.file,
    required this.contentType,
    required this.onUseVoiceCloneChanged,
    required this.onSelect,
    required this.onClear,
    this.onConsentChanged,
    super.key,
  });

  final bool enabled;
  final bool useVoiceClone;
  final bool consent;
  final XFile? file;
  final String? contentType;
  final ValueChanged<bool> onUseVoiceCloneChanged;
  final ValueChanged<bool>? onConsentChanged;
  final VoidCallback onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Material(
      color: palette.canvas,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: useVoiceClone,
              onChanged: enabled ? onUseVoiceCloneChanged : null,
              title: const Text('Use voice clone reference'),
              subtitle: const Text(
                'Choose a permitted voice sample of at least 6 seconds to guide the generated narration voice.',
              ),
            ),
            if (useVoiceClone) ...[
              IiOsGap.vSm,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      file == null
                          ? 'No voice reference selected'
                          : '${file!.name} · ${contentType ?? 'audio'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (file != null) ...[
                    IconButton(
                      tooltip: 'Remove voice reference',
                      onPressed: enabled ? onClear : null,
                      icon: const Icon(LucideIcons.x, size: 17),
                    ),
                    IiOsGap.hXs,
                  ],
                  OutlinedButton.icon(
                    onPressed: enabled ? onSelect : null,
                    icon: const Icon(LucideIcons.audioLines, size: 17),
                    label: Text(file == null ? 'Select audio' : 'Replace'),
                  ),
                ],
              ),
              IiOsGap.vSm,
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: enabled && onConsentChanged != null
                    ? (value) => onConsentChanged!(value ?? false)
                    : null,
                title: const Text(
                  'I have permission to use this voice reference.',
                ),
                subtitle: const Text(
                  'Do not upload another person\u2019s voice unless you have consent or the legal right to use it.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

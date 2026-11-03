import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';

class CharacterEssentials extends StatelessWidget {
  const CharacterEssentials({
    required this.name,
    required this.answers,
    required this.onChanged,
    required this.enabled,
    super.key,
  });

  final TextEditingController name;
  final Map<String, TextEditingController> answers;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('character-essentials'),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Character essentials'),
            const SizedBox(height: 5),
            Text(
              'These traits define the whole character and are carried into both the head and body sheets.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vMd,
            TextField(
              key: const ValueKey('character-name-field'),
              controller: name,
              enabled: enabled,
              onChanged: (_) => onChanged(),
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Character name (optional)',
                hintText: 'Name this character',
                prefixIcon: Icon(LucideIcons.userRound, size: 18),
              ),
            ),
            for (final question in characterSharedQuestions) ...[
              IiOsGap.vSm,
              Text(
                question.question,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IiOsGap.vXs,
              TextField(
                key: ValueKey('character-field-${question.key}'),
                controller: answers[question.key],
                enabled: enabled,
                onChanged: (_) => onChanged(),
                minLines: 2,
                maxLines: 5,
                maxLength: 1200,
                decoration: InputDecoration(
                  hintText: question.example,
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: IiOsColors.canvas,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

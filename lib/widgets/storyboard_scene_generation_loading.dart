import 'package:flutter/material.dart';

import '../theme/ii_os_tokens.dart';

class StoryboardSceneGenerationLoading extends StatelessWidget {
  const StoryboardSceneGenerationLoading({
    required this.count,
    this.expanded = false,
    super.key,
  });

  final int count;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? 'Generating 1 animated scene\u2026'
        : 'Generating $count animated scenes\u2026';
    return Card(
      child: SizedBox(
        height: expanded ? 300 : null,
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                IiOsGap.vSm,
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Completed videos will appear here and become the selected scene automatically.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

part of 'github_setup_onboarding.dart';

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({
    required this.stages,
    required this.activeId,
    required this.onSelected,
  });

  final List<GitHubSetupStageModel> stages;
  final String? activeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < stages.length; index++) ...[
        Expanded(
          child: _ProgressStep(
            number: index + 1,
            stage: stages[index],
            active: activeId == stages[index].id,
            enabled:
                stages[index].ready ||
                stages.take(index).every((stage) => stage.ready),
            onSelected: onSelected,
          ),
        ),
        if (index < stages.length - 1)
          Container(
            width: 22,
            height: 2,
            margin: const EdgeInsets.only(top: 17),
            color: stages[index].ready ? IiOsColors.green : IiOsColors.border,
          ),
      ],
    ],
  );
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.number,
    required this.stage,
    required this.active,
    required this.enabled,
    required this.onSelected,
  });

  final int number;
  final GitHubSetupStageModel stage;
  final bool active;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = stage.ready
        ? IiOsColors.green
        : active
        ? IiOsColors.blue
        : IiOsColors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(IiOsRadii.lg),
      onTap: enabled ? () => onSelected(stage.id) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
        child: Column(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: color.withValues(alpha: 0.12),
              child: stage.ready
                  ? Icon(LucideIcons.check, size: 18, color: color)
                  : Text(
                      '$number',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 7),
            Text(
              switch (stage.id) {
                'repository' => 'Repository',
                'permissions' => 'Permissions',
                'automation' => 'Automation',
                _ => 'Codex',
              },
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: active || stage.ready ? FontWeight.w800 : null,
              ),
            ),
            IiOsGap.vXxs,
            Text(
              stage.ready
                  ? 'Complete'
                  : active
                  ? 'Needs action'
                  : 'Later',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: active || stage.ready ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

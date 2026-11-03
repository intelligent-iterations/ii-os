part of 'github_setup_onboarding.dart';

class _CompletedStep extends StatelessWidget {
  const _CompletedStep({
    required this.stage,
    required this.number,
    required this.onContinue,
  });

  final GitHubSetupStageModel stage;
  final int number;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.greenTint,
      borderRadius: BorderRadius.circular(IiOsRadii.xl),
      border: Border.all(color: IiOsColors.green),
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            LucideIcons.circleCheckBig,
            color: IiOsColors.green,
            size: 34,
          ),
          IiOsGap.vSm,
          Text(
            _completionTitle(stage.id),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          IiOsGap.vXs,
          Text(_completionDetail(stage.id), textAlign: TextAlign.center),
          IiOsGap.vLg,
          Align(
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(LucideIcons.arrowRight, size: 17),
              label: Text(number == 2 ? 'Open Software Workshop' : 'Continue'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WorkshopReady extends StatelessWidget {
  const _WorkshopReady({required this.onOpenWorkshop});

  final VoidCallback onOpenWorkshop;

  @override
  Widget build(BuildContext context) => _CompletedStep(
    stage: const GitHubSetupStageModel(
      id: 'complete',
      title: 'GitHub connected',
      description: '',
      checks: [],
    ),
    number: 2,
    onContinue: onOpenWorkshop,
  );
}

class _SetupRecommendation extends StatelessWidget {
  const _SetupRecommendation({
    required this.check,
    required this.actionInProgress,
    required this.blockedReason,
    required this.onAction,
  });

  final GitHubSetupCheckModel check;
  final bool actionInProgress;
  final GitHubSetupBlockedReason blockedReason;
  final void Function(GitHubSetupAction, GitHubSetupCheckModel) onAction;

  @override
  Widget build(BuildContext context) {
    final warning = IiOsPalette.of(context).warning;
    final action = check.suggestedAction;
    final blocked = blockedReason(action);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning.container,
        border: Border.all(color: warning.text),
        borderRadius: BorderRadius.circular(IiOsRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.triangleAlert, color: warning.text, size: 19),
                IiOsGap.hXs,
                Expanded(
                  child: Text(
                    'Recommended: enable deployment verification',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: warning.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            IiOsGap.vXs,
            const Text(
              'GitHub setup and agent work can continue. Add Deployments read-only so ii-os can confirm the exact merged commit reached dev before offering Ready for QA.',
            ),
            IiOsGap.vSm,
            OutlinedButton.icon(
              onPressed: actionInProgress || blocked != null
                  ? null
                  : () => onAction(action, check),
              icon: const Icon(LucideIcons.externalLink, size: 17),
              label: const Text('Open permission settings'),
            ),
            InlineFormError(message: blocked),
          ],
        ),
      ),
    );
  }
}

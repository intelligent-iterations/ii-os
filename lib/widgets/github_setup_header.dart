part of 'github_setup_onboarding.dart';

/// The card's title bar.
///
/// It deliberately carries no progress count. The stepper directly below shows
/// position and completion, and the focused card states it in words; another
/// counter here counted a different thing (stages finished,
/// not stage you are on) and the two disagreed on screen.
class _WizardHeader extends StatelessWidget {
  const _WizardHeader({required this.ready, required this.loading});

  final bool ready;
  final bool loading;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: (ready ? IiOsColors.green : IiOsColors.blue).withValues(alpha: 0.07),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Row(
        children: [
          Icon(
            ready ? LucideIcons.circleCheckBig : LucideIcons.wandSparkles,
            color: ready ? IiOsColors.green : IiOsColors.blue,
            size: 25,
          ),
          IiOsGap.hSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? 'GitHub is connected' : 'Connect GitHub',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  ready
                      ? 'The App can reach the selected repository with the permissions required for agent work.'
                      : 'Two steps: verify the App connection, then grant repository access.',
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    ),
  );
}

class _RepositoryPicker extends StatelessWidget {
  const _RepositoryPicker({
    required this.repository,
    required this.repositories,
    required this.health,
    required this.statusLabel,
    required this.onChanged,
  });

  final String? repository;
  final List<String> repositories;
  final GitHubRepositoryHealthModel? health;
  final String? statusLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (repositories.length <= 1) {
      return Row(
        children: [
          const Icon(LucideIcons.gitBranch, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              repository ?? 'No repository selected yet',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (health != null)
            StatusPill(
              statusLabel ?? health!.label,
              color: health!.ready
                  ? IiOsColors.green
                  : health!.unavailable
                  ? IiOsColors.muted
                  : IiOsColors.amber,
            ),
        ],
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: repository,
      decoration: const InputDecoration(
        labelText: 'Repository to set up',
        prefixIcon: Icon(LucideIcons.gitBranch, size: 19),
      ),
      items: [
        for (final value in repositories)
          DropdownMenuItem(value: value, child: Text(value)),
      ],
      onChanged: onChanged,
    );
  }
}

String? _repositoryStatusLabel(
  GitHubRepositoryHealthModel? health,
  GitHubSetupStageModel? active,
) {
  if (health == null) return null;
  if (health.ready) return 'Ready';
  if (health.unavailable) return 'Couldn\u2019t verify';
  if (active == null) return 'Setup incomplete';
  return switch (active.id) {
    'permissions' => 'Permissions need action',
    'repository' => 'Repository needs action',
    'automation' => 'Automation needs action',
    _ => 'Codex needs action',
  };
}

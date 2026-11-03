library;

import 'github_setup_readiness.dart';

String setupTaskTitle(GitHubSetupCheckModel task) => switch (task.id) {
  'github_installation' => 'Connect your GitHub App',
  'repository_selected' => 'Choose a repository',
  'github_repository_access' => 'Verify the GitHub connection',
  'github_app_actions' ||
  'github_app_contents' ||
  'github_app_deployments' ||
  'github_app_pull_requests' => 'Give ii-os repository access',
  'permission_bootstrap_tag' => 'Mark this commit as reviewed',
  _ => 'Check the connection again',
};

String setupTaskExplanation(GitHubSetupCheckModel task) => switch (task.id) {
  'github_installation' =>
    'Ask an Organization Admin to add the GitHub App, then select that organization resource for this workspace.',
  'repository_selected' =>
    'Choose exactly which repository this GitHub App installation may use.',
  'github_repository_access' =>
    'The Firebase function uses the organization-owned App to request a short-lived GitHub installation token narrowed to this workspace and exact repository. No workflow or runner starts.',
  'github_app_actions' =>
    'Set Repository permissions → Actions to \u201cRead and write\u201d so ii-os can start the CI/CD workflows you approve.',
  'github_app_contents' =>
    'Set Repository permissions → Contents to \u201cRead and write\u201d so ii-os can read code and publish approved changes.',
  'github_app_deployments' =>
    'Set Repository permissions → Deployments to \u201cRead-only\u201d so ii-os can verify that the exact merged commit reached dev.',
  'github_app_pull_requests' =>
    'Set Repository permissions → Pull requests to \u201cRead and write\u201d so ii-os can create and update pull requests.',
  'permission_bootstrap_tag' =>
    'A person with write access creates this marker after reviewing the current dev commit. ii-os cannot create its own review proof.',
  _ =>
    'ii-os could not confirm this step yet. Open Technical details below to see exactly what it checked.',
};

String setupStepTitleFor(GitHubSetupCheckModel check) =>
    permissionSetupCheckIds.contains(check.id) ? 'Permissions' : 'Repository';

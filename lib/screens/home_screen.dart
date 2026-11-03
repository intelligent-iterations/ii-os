import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../services/mobile_update_platform.dart';
import '../state/app_controller.dart';
import '../view_models/home_view_model.dart';
import '../widgets/common.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import '../widgets/workspace_connection_row.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.controller,
    super.key,
    this.jobs,
    this.platformResolver = detectMobileUpdatePlatform,
    this.mobileUpdateRepository = AppConfig.mobileUpdateRepository,
  });

  final AppController controller;
  final JobRepository? jobs;
  final MobileUpdatePlatform? Function() platformResolver;
  final String mobileUpdateRepository;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.workspace!;
    final platform = platformResolver();
    // Refresh lives in the shell app bar, which already reports its own busy
    // state. A second button here ran the identical action and only disabled.
    return ViewModelBuilder<HomeViewModel>.reactive(
      viewModelBuilder: () => HomeViewModel(
        jobs: jobs ?? JobApiRepository(controller.api),
        workspaceId: workspace.id,
        platform: platform,
        canTriggerJobs: controller.can('jobs.trigger'),
        enabledWorkflows: workspace.workflows.toSet(),
        mobileUpdateRepository: mobileUpdateRepository,
      ),
      onViewModelReady: (viewModel) => viewModel.loadRecent(),
      builder: (context, viewModel, _) => PageFrame(
        title: 'Home',
        subtitle: workspace.name,
        actions: [
          if (platform != null)
            _MobileUpdateButton(
              enabled: viewModel.canUpdate,
              updating: viewModel.updating,
              tooltip: viewModel.tooltip,
              onPressed: () => _update(context, viewModel, platform),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KpiGrid(kpis: controller.dashboard),
            IiOsGap.vXl,
            const SectionTitle('Recent activity'),
            IiOsGap.vSm,
            _RecentActivity(
              jobs: viewModel.recent,
              loading: viewModel.loadingRecent,
            ),
            IiOsGap.vXl,
            const SectionTitle('Workspace connections'),
            IiOsGap.vSm,
            Card(
              child: Column(
                children: [
                  WorkspaceConnectionRow(
                    icon: LucideIcons.gitFork,
                    title: 'Repositories',
                    value: '${workspace.repositories.length}',
                    detail: workspace.repositories.isEmpty
                        ? 'No repositories configured'
                        : workspace.repositories.join(', '),
                  ),
                  const Divider(),
                  WorkspaceConnectionRow(
                    icon: LucideIcons.columns3,
                    title: 'Projects',
                    value: '${workspace.projects.length}',
                    detail: workspace.projects.isEmpty
                        ? 'No Projects configured'
                        : workspace.projects
                              .map((project) => project.title)
                              .join(', '),
                  ),
                  const Divider(),
                  WorkspaceConnectionRow(
                    icon: LucideIcons.workflow,
                    title: 'Workflows',
                    value: '${workspace.workflows.length}',
                    detail: workspace.workflows.isEmpty
                        ? 'No workflows configured'
                        : _workflowNames(workspace.workflows),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    HomeViewModel viewModel,
    MobileUpdatePlatform platform,
  ) async {
    final job = await viewModel.update();
    if (!context.mounted) return;
    if (job != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${platform.label} update queued.')),
      );
      return;
    }
    final error = viewModel.modelError;
    if (error != null) showFailure(context, error as Object);
  }
}

class _MobileUpdateButton extends StatelessWidget {
  const _MobileUpdateButton({
    required this.enabled,
    required this.updating,
    required this.tooltip,
    required this.onPressed,
  });

  final bool enabled;
  final bool updating;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: updating
            ? const SizedBox.square(
                dimension: IiOsSpacing.md,
                child: CircularProgressIndicator(
                  strokeWidth: IiOsSpacing.xxs / 2,
                ),
              )
            : const Icon(LucideIcons.refreshCw),
        label: const Text('Update'),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis});

  final JsonMap kpis;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final active = kpis['activeJobs'];
    final metrics = [
      (
        label: 'Active jobs',
        value: kpis['activeJobs'],
        hue: palette.brand,
        // The one metric that is a live state rather than a tally. Lifting it
        // is what makes a running job findable on a row of resting figures.
        caption: (active is num && active > 0) ? 'running' : null,
        emphasised: active is num && active > 0,
        emptyNote: null,
      ),
      (
        label: 'Completed jobs',
        value: kpis['completedJobs'],
        hue: palette.info,
        caption: null,
        emphasised: false,
        emptyNote: null,
      ),
      (
        label: 'Workshop tickets',
        value: kpis['openTickets'],
        hue: palette.warning,
        caption: null,
        emphasised: false,
        // An em dash alone reads as zero. Say which it is.
        emptyNote: 'not counted yet',
      ),
      (
        label: 'Members',
        value: kpis['members'],
        hue: palette.accent,
        caption: null,
        emphasised: false,
        emptyNote: null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= IiOsBreakpoints.expanded => 4,
          >= IiOsBreakpoints.pairedFields => 2,
          _ => 2,
        };
        final width =
            (constraints.maxWidth - (columns - 1) * IiOsSpacing.sm) / columns;
        return Wrap(
          spacing: IiOsSpacing.sm,
          runSpacing: IiOsSpacing.sm,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: KpiCard(
                  label: metric.label,
                  value: metric.value?.toString(),
                  hue: metric.hue,
                  caption: metric.caption,
                  emptyNote: metric.emptyNote,
                  emphasised: metric.emphasised,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Workflow keys are `owner/repo#file.yml`. Sixteen of them joined by commas
/// truncate to something nobody can read, so only the file names survive --
/// the repository is already named one row above.
String _workflowNames(List<String> workflows) => workflows
    .map((workflow) => workflow.split('#').last.replaceAll('.yml', ''))
    .join(' · ');

/// The last few jobs in the workspace.
///
/// Home counted work without ever showing any, which left the landing page --
/// and the destination every unreachable route falls back to -- mostly empty.
class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.jobs, required this.loading});

  final List<JsonMap> jobs;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.lg),
          child: Center(
            child: Text(
              loading ? 'Loading recent activity' : 'No jobs run yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (index, job) in jobs.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _RecentRow(job: job),
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.job});

  final JsonMap job;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final kind = (job['kind'] as String? ?? 'job')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');
    final repository = job['repository'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IiOsSpacing.md,
        vertical: IiOsSpacing.sm,
      ),
      child: Row(
        children: [
          StatusPill(job['status'] as String? ?? 'requested'),
          IiOsGap.hSm,
          Expanded(
            child: Text(
              kind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (repository.isNotEmpty) ...[
            IiOsMetaChip(label: repository.split('/').last),
            IiOsGap.hSm,
          ],
          Text(
            _shortDate(job['submittedAt']),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}

String _shortDate(Object? value) {
  final parsed = DateTime.tryParse(value as String? ?? '');
  if (parsed == null) return '\u2014';
  final local = parsed.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

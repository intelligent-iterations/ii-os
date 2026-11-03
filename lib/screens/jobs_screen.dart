import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/job_repository.dart';
import '../state/app_controller.dart';
import '../view_models/jobs_view_model.dart';
import '../widgets/common.dart';
import 'job_detail_sections.dart';
import 'jobs_table.dart';

/// The jobs list. Layout only -- loading, explicit refresh, and the stale flag live
/// in [JobsViewModel].
class JobsScreen extends StatelessWidget {
  const JobsScreen({
    required this.controller,
    this.selectedJobId,
    this.onSelectJob,
    this.onCloseJob,
    this.onJobViewed,
    super.key,
  });

  final AppController controller;
  final String? selectedJobId;
  final ValueChanged<String>? onSelectJob;
  final VoidCallback? onCloseJob;
  final ValueChanged<String>? onJobViewed;

  @override
  Widget build(BuildContext context) {
    final selectedJobId = this.selectedJobId;
    if (selectedJobId != null) {
      return _JobDetailView(
        controller: controller,
        workspaceId: controller.workspace!.id,
        jobId: selectedJobId,
        onClose: onCloseJob,
        onViewed: onJobViewed,
      );
    }
    return ViewModelBuilder<JobsViewModel>.reactive(
      viewModelBuilder: () => JobsViewModel(
        jobs: JobApiRepository(controller.api),
        workspaceId: controller.workspace!.id,
      ),
      onViewModelReady: (model) => model.start(),
      builder: (context, model, _) => PageFrame(
        title: 'Jobs',
        subtitle: 'GitHub Actions runs',
        actions: [
          OutlinedButton.icon(
            onPressed: model.isBusy ? null : model.load,
            icon: const Icon(LucideIcons.refreshCw, size: IiOsIconSize.md),
            label: const Text('Refresh'),
          ),
        ],
        child: _JobsBody(model: model, onSelectJob: onSelectJob),
      ),
    );
  }
}

/// Chooses between the stale banner, the failure, the empty state, and the
/// table, so `build()` above stays a description of the page.
class _JobsBody extends StatelessWidget {
  const _JobsBody({required this.model, required this.onSelectJob});

  final JobsViewModel model;
  final ValueChanged<String>? onSelectJob;

  @override
  Widget build(BuildContext context) {
    final error = model.errorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.stale) const _StaleBanner(),
        if (error != null && model.jobs.isEmpty)
          ErrorSurface(
            title: 'Jobs could not be loaded',
            message: error,
            onRetry: model.load,
          )
        else if (model.showLoadingSurface)
          const LoadingSurface(label: 'Loading jobs')
        else if (model.jobs.isEmpty)
          const Card(
            child: EmptyState(
              title: 'No jobs yet',
              message: 'Submitted media jobs will appear here.',
              icon: LucideIcons.activity,
            ),
          )
        else
          JobsTable(jobs: model.jobs, onSelectJob: onSelectJob),
      ],
    );
  }
}

/// The upstream refresh is lagging. The list below is real, so it stays on
/// screen and this says why it may be behind.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: IiOsSpacing.sm),
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      decoration: BoxDecoration(
        color: IiOsColors.amberTint,
        border: Border.all(color: IiOsColors.amber),
        borderRadius: IiOsRadii.mdAll,
      ),
      child: const Row(
        children: [
          Icon(
            LucideIcons.cloudOff,
            size: IiOsIconSize.md,
            color: IiOsColors.amber,
          ),
          IiOsGap.hXs,
          Expanded(child: Text('GitHub status is temporarily unavailable.')),
        ],
      ),
    );
  }
}

/// The job listing table, kept as a standalone widget so its metadata and
/// click-through contract can be verified independently of API refresh behavior.
class _JobDetailView extends StatefulWidget {
  const _JobDetailView({
    required this.controller,
    required this.workspaceId,
    required this.jobId,
    required this.onClose,
    this.onViewed,
  });

  final AppController controller;
  final String workspaceId;
  final String jobId;
  final VoidCallback? onClose;
  final ValueChanged<String>? onViewed;

  @override
  State<_JobDetailView> createState() => _JobDetailViewState();
}

class _JobDetailViewState extends State<_JobDetailView> {
  late Future<JsonMap> _future = _load();

  @override
  void didUpdateWidget(covariant _JobDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.workspaceId != widget.workspaceId) {
      _future = _load();
      widget.onViewed?.call(widget.jobId);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.onViewed?.call(widget.jobId);
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Job detail',
      subtitle: widget.jobId,
      actions: [
        TextButton.icon(
          onPressed: widget.onClose,
          icon: const Icon(LucideIcons.arrowLeft, size: 17),
          label: const Text('Jobs'),
        ),
      ],
      child: SizedBox(
        height: 620,
        child: FutureBuilder<JsonMap>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return EmptyState(
                title: 'Job detail unavailable',
                message: snapshot.error.toString(),
                icon: LucideIcons.triangleAlert,
              );
            }
            final job = asJsonMap(snapshot.data?['job']);
            final events = (job['events'] as List<Object?>? ?? const [])
                .map(asJsonMap)
                .toList();
            final artifacts = (job['artifacts'] as List<Object?>? ?? const [])
                .map(asJsonMap)
                .toList();
            final runtimeEstimate = RuntimeEstimateSnapshot.fromJob(
              job['runtimeEstimate'],
            );
            final totalElapsed = _totalElapsed(job);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(IiOsSpacing.lg),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _Fact('Status', job['status']?.toString() ?? 'requested'),
                      _Fact('Work type', jobWorkTypeLabel(job['workType'])),
                      _Fact(
                        'Workflow',
                        job['workflowName']?.toString() ??
                            job['kind']?.toString() ??
                            '\u2014',
                      ),
                      _Fact(
                        'Repository',
                        job['repository']?.toString() ?? '\u2014',
                      ),
                      _Fact('Ref', job['workflowRef']?.toString() ?? '\u2014'),
                      _Fact(
                        'GitHub run',
                        job['githubRunId']?.toString() ?? 'Pending',
                      ),
                      if (runtimeEstimate != null)
                        _Fact(
                          'Estimated GPU time',
                          'About ${runtimeEstimate.durationLabel}',
                        ),
                      if (runtimeEstimate != null)
                        _Fact('Estimated hardware', runtimeEstimate.hardware),
                      if (totalElapsed != null)
                        _Fact('Total elapsed', totalElapsed),
                    ],
                  ),
                ),
                const Divider(),
                if (artifacts.isNotEmpty)
                  JobArtifactsSection(
                    controller: widget.controller,
                    workspaceId: widget.workspaceId,
                    jobId: widget.jobId,
                    artifacts: artifacts,
                  ),
                Expanded(
                  child: events.isEmpty
                      ? const EmptyState(
                          title: 'No lifecycle events',
                          message:
                              'GitHub events will appear as the run advances.',
                          icon: LucideIcons.listTree,
                        )
                      : JobEventsSection(events: events),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Through the repository rather than the API client: the URL and its
  // encoding belong to one owner. The detail view keeps its FutureBuilder for
  // now; converting it to a ViewModel is the next step on this page.
  Future<JsonMap> _load() => JobApiRepository(
    widget.controller.api,
  ).detail(widget.workspaceId, widget.jobId);
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

String? _totalElapsed(JsonMap job) {
  final submitted = DateTime.tryParse(job['submittedAt']?.toString() ?? '');
  final completed = DateTime.tryParse(job['completedAt']?.toString() ?? '');
  if (submitted == null || completed == null || completed.isBefore(submitted)) {
    return null;
  }
  return formatRuntimeSeconds(completed.difference(submitted).inSeconds);
}

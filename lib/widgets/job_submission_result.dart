import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../services/polling_cost_policy.dart';
import '../state/app_controller.dart';
import '../state/app_controller_ghost.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';
import 'generated_media_surface.dart';
import 'runtime_estimate_notice.dart';

export 'generated_media_surface.dart'
    show GeneratedMediaKind, GeneratedMediaLoadingSurface;

part 'job_submission_result_recovery.dart';

class JobSubmissionResult extends StatefulWidget {
  const JobSubmissionResult({
    required this.controller,
    required this.result,
    this.title = 'Job submitted',
    this.mediaKind,
    this.mediaAspectRatio,
    this.mediaLabel,
    this.onChanged,
    this.onRetry,
    super.key,
  });

  final AppController controller;
  final JsonMap result;
  final String title;
  final GeneratedMediaKind? mediaKind;
  final double? mediaAspectRatio;
  final String? mediaLabel;
  final ValueChanged<JsonMap>? onChanged;
  final Future<void> Function()? onRetry;

  @override
  State<JobSubmissionResult> createState() => _JobSubmissionResultState();
}

class _JobSubmissionResultState extends State<JobSubmissionResult> {
  late JsonMap _result = widget.result;
  Timer? _listener;
  bool _refreshing = false;
  bool _cancelling = false;
  bool _retrying = false;
  bool _ghostCleanupStarted = false;
  Object? _ghostCleanupError;

  @override
  void initState() {
    super.initState();
    _syncListener();
  }

  @override
  void didUpdateWidget(covariant JobSubmissionResult oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result['jobId'] != widget.result['jobId'] ||
        (!_cancelling &&
            oldWidget.result['status'] != widget.result['status'])) {
      if (oldWidget.result['jobId'] != widget.result['jobId']) {
        _ghostCleanupStarted = false;
        _ghostCleanupError = null;
      }
      _result = widget.result;
      _cancelling = false;
      _syncListener();
    }
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _result['status'] as String? ?? 'requested';
    final kind = widget.mediaKind;
    final artifactMissing = _displayArtifactMissing(_result, kind, status);
    final failed = status == 'failed' || artifactMissing;
    final errorCode = _jobErrorCode(_result);
    final runtimeEstimate = RuntimeEstimateSnapshot.fromJob(
      _result['runtimeEstimate'],
    );
    final canCancel =
        widget.controller.can('jobs.trigger') &&
        _cancellableJobStatuses.contains(status) &&
        !_cancelling;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.mediaKind case final kind?) ...[
              GeneratedMediaSurface(
                key: ValueKey(
                  '${_result['jobId']}-'
                  '${generatedMediaArtifact(_result, kind)?['path']}',
                ),
                controller: widget.controller,
                job: _result,
                kind: kind,
                aspectRatio: widget.mediaAspectRatio,
                mediaLabel: widget.mediaLabel,
              ),
              IiOsGap.vMd,
            ],
            _JobStatusRow(
              active: generatedMediaJobIsActive(status),
              failed: failed,
              cancelling: _cancelling,
              artifactMissing: artifactMissing,
              status: status,
              title: widget.title,
              jobId: _result['jobId'] as String? ?? '',
            ),
            if (runtimeEstimate != null) ...[
              IiOsGap.vSm,
              RuntimeEstimateNotice(estimate: runtimeEstimate),
            ],
            if (failed)
              _FailedJobRecovery(
                message: _failureMessage(artifactMissing, errorCode),
                retrying: _retrying,
                onRetry: _retryAvailable(failed) ? _retry : null,
              ),
            if (_result['ghostMode'] == true && _ghostCleanupError != null) ...[
              IiOsGap.vSm,
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const Key('ghost-terminal-cleanup-retry'),
                  onPressed: _cleanupTerminalGhost,
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  label: const Text('Delete temporary data'),
                ),
              ),
            ],
            if (canCancel) ...[
              IiOsGap.vSm,
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(LucideIcons.circleStop, size: 16),
                  label: const Text('Cancel job'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    final jobId = _result['jobId'] as String? ?? '';
    final workspaceId = widget.controller.workspace?.id ?? '';
    if (jobId.isEmpty || workspaceId.isEmpty || _cancelling) return;
    setState(() => _cancelling = true);
    var requested = false;
    try {
      final response = await widget.controller.api.post(
        'v1/workspaces/$workspaceId/jobs/'
        '${Uri.encodeComponent(jobId)}/cancel',
      );
      if (!mounted) return;
      setState(() => _result = asJsonMap(response['data']));
      _syncListener();
      requested = true;
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
    if (requested) await _refresh();
  }

  Future<void> _retry() async {
    final retry = widget.onRetry;
    if (retry == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      await retry();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  void _syncListener() {
    final status = _result['status'] as String? ?? 'requested';
    if (!generatedMediaJobIsActive(status)) {
      _listener?.cancel();
      _listener = null;
      final terminalFailure = status == 'failed' || status == 'cancelled';
      final missingDisplayArtifact =
          widget.mediaKind != null &&
          generatedMediaArtifact(_result, widget.mediaKind!) == null;
      if (_result['ghostMode'] == true &&
          (terminalFailure || missingDisplayArtifact)) {
        _cleanupTerminalGhost();
      }
      return;
    }
    _listener ??= Timer.periodic(
      IiOsPollingCostPolicy.activeOperation,
      (_) => unawaited(_refresh()),
    );
  }

  void _cleanupTerminalGhost() {
    if (_ghostCleanupStarted) return;
    final jobId = _result['jobId'] as String? ?? '';
    if (jobId.isEmpty) return;
    _ghostCleanupStarted = true;
    if (_ghostCleanupError != null && mounted) {
      setState(() => _ghostCleanupError = null);
    }
    unawaited(
      widget.controller.consumeGhostJob(jobId).catchError((Object error) {
        if (mounted) {
          setState(() {
            _ghostCleanupStarted = false;
            _ghostCleanupError = error;
          });
          showFailure(context, error);
        } else {
          _ghostCleanupStarted = false;
          _ghostCleanupError = error;
        }
      }),
    );
  }

  Future<void> _refresh() async {
    final jobId = _result['jobId'] as String? ?? '';
    final workspaceId = widget.controller.workspace?.id ?? '';
    if (!mounted || _refreshing || jobId.isEmpty || workspaceId.isEmpty) return;
    _refreshing = true;
    try {
      final response = await widget.controller.api.get(
        'v1/workspaces/$workspaceId/jobs/${Uri.encodeComponent(jobId)}',
      );
      final job = asJsonMap(response['job']);
      if (!mounted || job['jobId'] != jobId) return;
      setState(() => _result = job);
      _syncListener();
      widget.onChanged?.call(job);
      final status = job['status'] as String? ?? '';
      if (_terminalJobStatuses.contains(status)) {
        _listener?.cancel();
        _listener = null;
        unawaited(widget.controller.refreshDashboard());
      }
    } on Object {
      // A transient refresh failure must not stop the completion listener.
    } finally {
      _refreshing = false;
    }
  }

  String _mediaDescription() => switch (widget.mediaKind) {
    GeneratedMediaKind.video => 'a video',
    GeneratedMediaKind.audio => 'a ${_mediaNoun()}',
    GeneratedMediaKind.image || null => 'an image',
  };

  String _mediaNoun() => switch (widget.mediaKind) {
    GeneratedMediaKind.video => 'video',
    GeneratedMediaKind.audio => _audioMediaLabel(),
    GeneratedMediaKind.image || null => 'image',
  };

  String _audioMediaLabel() {
    final label = widget.mediaLabel?.trim();
    return label == null || label.isEmpty ? 'song' : label;
  }
}

class _JobStatusRow extends StatelessWidget {
  const _JobStatusRow({
    required this.active,
    required this.failed,
    required this.cancelling,
    required this.artifactMissing,
    required this.status,
    required this.title,
    required this.jobId,
  });

  final bool active;
  final bool failed;
  final bool cancelling;
  final bool artifactMissing;
  final String status;
  final String title;
  final String jobId;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (active)
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        Icon(
          failed
              ? LucideIcons.circleAlert
              : status == 'cancelled'
              ? LucideIcons.circleStop
              : LucideIcons.circleCheck,
          color: failed
              ? IiOsColors.red
              : status == 'cancelled'
              ? IiOsColors.muted
              : IiOsColors.green,
          size: 20,
        ),
      IiOsGap.hSm,
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            IiOsGap.vXxs,
            SelectableText(
              jobId,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      StatusPill(
        cancelling
            ? 'cancelling'
            : artifactMissing
            ? 'artifact missing'
            : status,
      ),
    ],
  );
}

const _cancellableJobStatuses = {
  'dispatching',
  'dispatched',
  'queued',
  'requested',
  'running',
  'in_progress',
  'pending',
};

const _terminalJobStatuses = {'completed', 'failed', 'cancelled'};

String? _jobErrorCode(JsonMap result) {
  final direct = result['errorCode'];
  if (direct is String && direct.isNotEmpty) return direct;
  final workflowResult = result['workflowResult'];
  if (workflowResult is Map) {
    final nested = workflowResult['errorCode'];
    if (nested is String && nested.isNotEmpty) return nested;
  }
  return null;
}

bool _displayArtifactMissing(
  JsonMap result,
  GeneratedMediaKind? kind,
  String status,
) =>
    kind != null &&
    status == 'completed' &&
    generatedMediaArtifact(result, kind) == null;

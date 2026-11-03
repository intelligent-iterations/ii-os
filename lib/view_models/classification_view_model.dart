import 'dart:async';

import 'package:stacked/stacked.dart';

import '../models/classification_decisions.dart';
import '../models/classification_questions.dart';
import '../models/models.dart';
import '../repositories/classification_result_repository.dart';
import '../repositories/job_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../services/api_client.dart';
import '../services/polling_cost_policy.dart';
import 'classification_form_editing.dart';
import 'playground_view_model.dart';

/// Where the one classification run this page started currently stands.
///
/// [paused] means the run is still active on the server but this page stopped
/// asking after [classificationWatchCeiling]; the person can resume watching.
enum ClassificationRunPhase {
  idle,
  submitting,
  running,
  paused,
  reading,
  completed,
  failed,
}

/// The longest this page keeps reading an active job without being asked.
///
/// A run can sit behind a long render on the same GPU. Without a ceiling an
/// open tab would read the job every two seconds for as long as it waited.
const classificationWatchCeiling = Duration(minutes: 20);

const _activeStatuses = {
  'dispatching',
  'dispatched',
  'queued',
  'requested',
  'running',
  'in_progress',
  'pending',
  'cancelling',
};

final class ClassificationViewModel extends BaseViewModel
    with ClassificationFormEditing {
  ClassificationViewModel({
    required this._templates,
    required this._jobs,
    required this._results,
    required this.workspaceId,
    required this.expectedBucket,
    this._ghostMode = false,
    this.onFinished,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _watchStartedAt;

  final WorkflowTemplateRepository _templates;
  final JobRepository _jobs;
  final ClassificationResultRepository _results;
  final String workspaceId;
  final String expectedBucket;

  /// Called once when a run reaches a terminal state.
  final Future<void> Function()? onFinished;

  bool _ghostMode;
  bool get ghostMode => _ghostMode;

  List<WorkflowTemplateModel> templates = const [];
  bool loaded = false;
  ClassificationRunPhase phase = ClassificationRunPhase.idle;
  JsonMap? job;
  ClassificationDecisions? decisions;
  String? failureMessage;
  Timer? _listener;
  bool _refreshing = false;
  bool _disposed = false;

  WorkflowTemplateModel? get template => resolveSelectedTemplate(templates);

  ClassificationAvailability get availability => loaded
      ? classificationAvailabilityOf(templates)
      : ClassificationAvailability.checking;

  bool get showsUnavailableNotice =>
      loaded && (template == null || !template!.enabled);

  bool get running =>
      phase == ClassificationRunPhase.submitting ||
      phase == ClassificationRunPhase.running ||
      phase == ClassificationRunPhase.paused ||
      phase == ClassificationRunPhase.reading;

  /// Whether the active-operation listener is currently reading the job.
  bool get watching => _listener != null;

  bool get canSubmit => template?.enabled == true && issues.isEmpty && !running;

  /// Why launching is not possible right now, for the line beside the button;
  /// null while there is nothing to explain.
  String? get launchBlockedReason {
    if (!loaded || running) return null;
    final selected = template;
    if (selected == null || !selected.enabled) {
      return selected?.disabledReason.isNotEmpty == true
          ? selected!.disabledReason
          : 'Classification is not set up for this workspace yet.';
    }
    final problems = issues;
    for (final issue in problems) {
      if (issue.questionKey == null) return issue.message;
    }
    return problems.isEmpty
        ? null
        : 'Fix the highlighted question before classifying.';
  }

  Future<void> load() async {
    try {
      templates = await _templates.list(
        workspaceId,
        workflowIdPrefix: classificationWorkflowIdPrefix,
      );
    } on Object {
      templates = const [];
    }
    loaded = true;
    _notify();
  }

  void setGhostMode(bool value) {
    if (_ghostMode == value || running) return;
    _ghostMode = value;
  }

  Future<void> submit() async {
    final selected = template;
    if (selected == null || !canSubmit) return;
    _stopListener();
    phase = ClassificationRunPhase.submitting;
    job = null;
    decisions = null;
    failureMessage = null;
    _notify();
    try {
      job = await _jobs.submit(
        workspaceId,
        JobSubmission(
          workflowKey: selected.id,
          pageSlug: 'playground',
          ghostMode: _ghostMode,
          input: {
            'state': stateText.trim(),
            'questions': encodeClassificationQuestions(questions),
          },
        ),
      );
      phase = ClassificationRunPhase.running;
      _watchStartedAt = _clock();
      _notify();
      await _apply(job!);
    } on ApiFailure catch (failure) {
      _failed(classificationFailureMessage(failure.code));
    } on Object {
      _failed(classificationFailureMessage(null));
    }
  }

  /// One read of the submitted job. The listener calls this every
  /// [IiOsPollingCostPolicy.activeOperation] until a terminal state.
  Future<void> refreshJob() async {
    final jobId = job?['jobId'] as String? ?? '';
    if (_refreshing ||
        jobId.isEmpty ||
        phase != ClassificationRunPhase.running) {
      return;
    }
    if (_clock().difference(_watchStartedAt ?? _clock()) >=
        classificationWatchCeiling) {
      _stopListener();
      phase = ClassificationRunPhase.paused;
      _notify();
      return;
    }
    _refreshing = true;
    try {
      final latest = asJsonMap((await _jobs.detail(workspaceId, jobId))['job']);
      if (latest['jobId'] == jobId) await _apply(latest);
    } on Object {
      // A transient read failure must not stop the completion listener.
    } finally {
      _refreshing = false;
    }
  }

  /// Starts a fresh watch window after a pause, with one immediate read.
  Future<void> resumeWatching() async {
    if (phase != ClassificationRunPhase.paused) return;
    phase = ClassificationRunPhase.running;
    _watchStartedAt = _clock();
    _notify();
    await refreshJob();
    if (phase == ClassificationRunPhase.running && job != null) {
      await _apply(job!);
    }
  }

  Future<void> _apply(JsonMap latest) async {
    job = latest;
    final status = latest['status'] as String? ?? 'requested';
    if (_activeStatuses.contains(status)) {
      _listener ??= Timer.periodic(
        IiOsPollingCostPolicy.activeOperation,
        (_) => unawaited(refreshJob()),
      );
      _notify();
      return;
    }
    _stopListener();
    if (status == 'completed') {
      await _readResult(latest);
    } else {
      _failed(
        classificationFailureMessage(
          status == 'cancelled'
              ? 'classification_workflow_cancelled'
              : _errorCode(latest),
        ),
      );
      _releaseGhost(latest);
    }
    unawaited(onFinished?.call());
  }

  Future<void> _readResult(JsonMap completed) async {
    phase = ClassificationRunPhase.reading;
    _notify();
    final artifact = decisionsArtifact(completed);
    try {
      if (artifact == null) {
        throw const FormatException('No decisions document was reported.');
      }
      decisions = await _results.readDecisions(
        workspaceId: workspaceId,
        jobId: completed['jobId'] as String,
        expectedBucket: expectedBucket,
        artifact: artifact,
      );
      phase = ClassificationRunPhase.completed;
      _notify();
    } on Object {
      _failed(classificationFailureMessage('classification_result_unreadable'));
    }
    _releaseGhost(completed);
  }

  void _releaseGhost(JsonMap finished) {
    if (finished['ghostMode'] != true) return;
    unawaited(
      _results
          .consumeGhostJob(
            workspaceId: workspaceId,
            jobId: finished['jobId'] as String? ?? '',
          )
          .catchError((Object _) {}),
    );
  }

  void _failed(String message) {
    _stopListener();
    phase = ClassificationRunPhase.failed;
    failureMessage = message;
    _notify();
  }

  void _stopListener() {
    _listener?.cancel();
    _listener = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListener();
    super.dispose();
  }
}

String? _errorCode(JsonMap job) {
  final direct = job['errorCode'];
  if (direct is String && direct.isNotEmpty) return direct;
  final result = job['workflowResult'];
  if (result is Map && result['errorCode'] is String) {
    return result['errorCode'] as String;
  }
  return null;
}

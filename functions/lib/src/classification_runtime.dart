import 'api_error.dart';

/// Catalog workflows whose execution needs the open JEV decision runtime.
const classificationWorkflowIdPrefix = 'classification-';

/// The capability a reported host advertises only once the pinned open JEV
/// image and its verified model weights are installed on it.
const classificationRequiredCapabilities = <String>['open-jev-9b'];

const classificationRuntimeUnavailableReason =
    'No runner has the classification model installed yet.';
const classificationRuntimeUnknownReason =
    'Waiting for your runners to confirm the classification model is '
    'installed.';

const runnerCapacityProviderSetting = 'II_OS_RUNNER_CAPACITY_PROVIDER';

/// Whether classification can run right now, as runner capacity reports say.
///
/// `unknown` is kept distinct from `unavailable`: a missing, stale, or
/// unreadable report says nothing about the hosts, so the UI must not claim the
/// runtime is absent when it only failed to find out. `notReported` means the
/// deployment receives no capacity reports at all: classification is offered,
/// and the workflow's own model-folder check names a missing model at run time.
enum ClassificationRuntimeStatus {
  unknown,
  unavailable,
  available,
  notReported,
}

/// Where a deployment's runner capacity reports come from.
///
/// `fleet` reads each organization's runner control-plane report (the stored
/// `fleetSnapshots` document). `none` declares that the deployment receives no
/// capacity reports, so nothing is read.
enum RunnerCapacityProvider { fleet, none }

/// Parses [runnerCapacityProviderSetting]; an unsupported value stops startup.
RunnerCapacityProvider parseRunnerCapacityProvider(String value) =>
    switch (value.trim()) {
      'fleet' => RunnerCapacityProvider.fleet,
      'none' => RunnerCapacityProvider.none,
      _ => throw const FormatException(
        '$runnerCapacityProviderSetting must be fleet or none.',
      ),
    };

/// The composition root's one place that turns the setting into a reader.
ClassificationRuntimeGate classificationRuntimeGateFor(
  RunnerCapacityProvider provider, {
  required FleetSnapshotReader fleetReports,
}) => ClassificationRuntimeGate(
  reader: switch (provider) {
    RunnerCapacityProvider.fleet => fleetReports,
    RunnerCapacityProvider.none => null,
  },
);

/// Reads the latest fleet report for one organization, or null if none exists.
///
/// The shape is the provider-neutral `FleetSnapshotStore.read` result:
/// `{stale: bool, hosts: [{health, drain, capabilities, ...}]}`.
typedef FleetSnapshotReader =
    Future<Map<String, Object?>?> Function(String organizationId);

bool isClassificationWorkflow(String workflowId) =>
    workflowId.startsWith(classificationWorkflowIdPrefix);

ClassificationRuntimeStatus evaluateClassificationRuntime(
  Map<String, Object?>? snapshot,
) {
  if (snapshot == null || snapshot['stale'] != false) {
    return ClassificationRuntimeStatus.unknown;
  }
  final hosts = snapshot['hosts'];
  if (hosts is! List) return ClassificationRuntimeStatus.unknown;
  for (final host in hosts) {
    if (host is! Map) continue;
    final capabilities = host['capabilities'];
    if (host['health'] == 'ok' &&
        host['drain'] != true &&
        capabilities is List &&
        classificationRequiredCapabilities.every(capabilities.contains)) {
      return ClassificationRuntimeStatus.available;
    }
  }
  return ClassificationRuntimeStatus.unavailable;
}

/// One fleet-report read per organization per [ttl], shared by concurrent
/// callers. A failed read is cached as `unknown` for the same window so an
/// outage cannot turn every page load into a fresh database read. Without a
/// [reader] the deployment receives no capacity reports: every status is
/// `notReported` and nothing is read.
final class ClassificationRuntimeGate {
  ClassificationRuntimeGate({
    this.reader,
    this.ttl = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  final FleetSnapshotReader? reader;
  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, _GateEntry> _entries = {};

  Future<ClassificationRuntimeStatus> status(String organizationId) {
    final read = reader;
    if (read == null) {
      return Future.value(ClassificationRuntimeStatus.notReported);
    }
    if (organizationId.isEmpty) {
      return Future.value(ClassificationRuntimeStatus.unknown);
    }
    final now = _clock();
    final cached = _entries[organizationId];
    if (cached != null && now.isBefore(cached.createdAt.add(ttl))) {
      return cached.status;
    }
    final status = _read(read, organizationId);
    _entries[organizationId] = _GateEntry(status: status, createdAt: now);
    return status;
  }

  Future<ClassificationRuntimeStatus> _read(
    FleetSnapshotReader read,
    String organizationId,
  ) async {
    try {
      return evaluateClassificationRuntime(await read(organizationId));
    } on Object {
      return ClassificationRuntimeStatus.unknown;
    }
  }
}

final class _GateEntry {
  const _GateEntry({required this.status, required this.createdAt});

  final Future<ClassificationRuntimeStatus> status;
  final DateTime createdAt;
}

/// Adds the runtime requirement to a template and narrows `enabled`.
///
/// Workspace selection is decided first and its reason wins: an operator who
/// has not enabled the workflow needs that instruction, not a runner one.
Map<String, Object?> applyClassificationRuntime(
  Map<String, Object?> template,
  ClassificationRuntimeStatus status,
) {
  final selected = template['enabled'] == true;
  return {
    ...template,
    'enabled': selected && classificationRuntimeAdmits(status),
    'disabledReason': !selected
        ? template['disabledReason']
        : switch (status) {
            ClassificationRuntimeStatus.available ||
            ClassificationRuntimeStatus.notReported => '',
            ClassificationRuntimeStatus.unavailable =>
              classificationRuntimeUnavailableReason,
            ClassificationRuntimeStatus.unknown =>
              classificationRuntimeUnknownReason,
          },
    'runtime': {
      'status': status.name,
      'requiredCapabilities': classificationRequiredCapabilities,
    },
  };
}

/// Whether a classification run may be offered and dispatched.
///
/// Reported capacity must show the runtime installed. A deployment that
/// reports no capacity admits the run and lets the workflow check its model.
bool classificationRuntimeAdmits(ClassificationRuntimeStatus status) =>
    status == ClassificationRuntimeStatus.available ||
    status == ClassificationRuntimeStatus.notReported;

/// Refuses a classification dispatch reported runner capacity cannot place.
void requireClassificationRuntime(ClassificationRuntimeStatus status) {
  if (classificationRuntimeAdmits(status)) return;
  throw ApiError(
    409,
    'classification_runtime_unavailable',
    status == ClassificationRuntimeStatus.unknown
        ? classificationRuntimeUnknownReason
        : classificationRuntimeUnavailableReason,
  );
}

DateTime _utcNow() => DateTime.now().toUtc();

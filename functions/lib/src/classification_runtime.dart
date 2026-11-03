import 'api_error.dart';

/// Catalog workflows whose execution needs the open JEV decision runtime.
const classificationWorkflowIdPrefix = 'classification-';

/// The Fleet capability a host advertises only once the pinned open JEV image
/// and its verified model weights are installed on it.
const classificationRequiredCapabilities = <String>['open-jev-9b'];

const classificationRuntimeUnavailableReason =
    'Waiting for the open JEV runtime image to be installed on a Fleet GPU '
    'host.';
const classificationRuntimeUnknownReason =
    'Waiting for a fresh Fleet report to confirm the open JEV runtime.';

/// Whether an organization's own Fleet can run classification right now.
///
/// `unknown` is kept distinct from `unavailable`: a missing, stale, or
/// unreadable report says nothing about the hosts, so the UI must not claim the
/// runtime is absent when it only failed to find out.
enum ClassificationRuntimeStatus { unknown, unavailable, available }

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
/// outage cannot turn every page load into a fresh database read.
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
    if (read == null || organizationId.isEmpty) {
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
/// has not enabled the workflow needs that instruction, not a Fleet one.
Map<String, Object?> applyClassificationRuntime(
  Map<String, Object?> template,
  ClassificationRuntimeStatus status,
) {
  final selected = template['enabled'] == true;
  final available = status == ClassificationRuntimeStatus.available;
  return {
    ...template,
    'enabled': selected && available,
    'disabledReason': !selected
        ? template['disabledReason']
        : switch (status) {
            ClassificationRuntimeStatus.available => '',
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

/// Refuses a classification dispatch the organization's Fleet cannot place.
void requireClassificationRuntime(ClassificationRuntimeStatus status) {
  if (status == ClassificationRuntimeStatus.available) return;
  throw ApiError(
    409,
    'classification_runtime_unavailable',
    status == ClassificationRuntimeStatus.unknown
        ? classificationRuntimeUnknownReason
        : classificationRuntimeUnavailableReason,
  );
}

DateTime _utcNow() => DateTime.now().toUtc();

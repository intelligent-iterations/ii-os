import 'organization_resources.dart';

/// What a person states about runners they already run.
///
/// ii-os never creates or connects to these runners. A workflow still chooses
/// where it runs; these limits cap what a workspace granted the pool may ask
/// for, and dispatch requires one such grant.
final class CustomerRunnerPoolInput {
  const CustomerRunnerPoolInput({
    required this.name,
    required this.runnerGroup,
    required this.capabilities,
    required this.maxCpu,
    required this.maxRamMiB,
    required this.maxConcurrent,
    this.active = true,
  });

  final String name;

  /// The name the person's workflows use for these runners.
  final String runnerGroup;
  final Set<String> capabilities;
  final int maxCpu;
  final int maxRamMiB;
  final int maxConcurrent;

  /// Whether workspaces may use the pool. Turning it off is how a pool kept
  /// by hand is retired; its grants become stale rather than silently moving.
  final bool active;

  OrganizationRunnerPoolDraft toDraft(String id) => OrganizationRunnerPoolDraft(
    id: id,
    name: name,
    provider: customerRunnerProvider,
    capabilities: capabilities,
    maxCpu: maxCpu,
    maxRamMiB: maxRamMiB,
    maxConcurrent: maxConcurrent,
    providerPoolId: runnerGroup,
    active: active,
  );
}

/// A catalog id for a new pool named [name] that no pool in [taken] holds.
///
/// The server upserts by id, so reusing one would silently replace a pool.
/// Ids match `^[a-z][a-z0-9_]{2,63}$`; the base leaves room for a suffix.
String customerRunnerPoolId(String name, Iterable<String> taken) {
  const prefix = 'runner_';
  const maxBase = 56;
  final used = taken.toSet();
  var slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) slug = 'pool';
  var base = '$prefix$slug';
  if (base.length > maxBase) {
    base = base.substring(0, maxBase).replaceAll(RegExp(r'_+$'), '');
  }
  if (!used.contains(base)) return base;
  for (var suffix = 2; ; suffix += 1) {
    final candidate = '${base}_$suffix';
    if (!used.contains(candidate)) return candidate;
  }
}

/// Capability names from a comma-separated field.
Set<String> parseRunnerCapabilities(String text) => text
    .split(',')
    .map((item) => item.trim().toLowerCase())
    .where((item) => item.isNotEmpty)
    .toSet();

/// Why a runner pool change did not land, named for what the person can do.
enum RunnerPoolFailureKind {
  /// No capacity report has ever arrived for this organization.
  notReported,

  /// The last capacity report is too old to trust.
  staleReport,

  /// The report arrived but lists no runner a workspace can use.
  noReportedCapacity,

  /// The organization already holds as many runner pools as it may.
  limitReached,

  /// The pool came from a capacity report and changes only through a sync.
  reportedPool,

  /// The server refused the values, such as a capability name.
  invalid,

  /// The viewer's organization role cannot manage runners.
  forbidden,

  /// Anything else; retrying may help.
  unknown,
}

final class RunnerPoolFailure implements Exception {
  const RunnerPoolFailure(this.kind);

  final RunnerPoolFailureKind kind;

  @override
  String toString() => 'RunnerPoolFailure(${kind.name})';
}

/// Whether the execution runtime a workflow needs is installed right now.
///
/// The server decides this from the organization's own Fleet report. `unknown`
/// is its own state: a missing or stale report says nothing about the hosts,
/// so the surface must not render it as either installed or absent.
enum WorkflowRuntimeStatus { unknown, unavailable, available }

final class WorkflowRuntimeRequirement {
  const WorkflowRuntimeRequirement({
    required this.status,
    this.requiredCapabilities = const [],
  });

  /// Null when the template declares no runtime requirement at all.
  static WorkflowRuntimeRequirement? fromJson(Object? value) {
    if (value is! Map) return null;
    final capabilities = value['requiredCapabilities'];
    return WorkflowRuntimeRequirement(
      status: switch (value['status']) {
        'available' => WorkflowRuntimeStatus.available,
        'unavailable' => WorkflowRuntimeStatus.unavailable,
        _ => WorkflowRuntimeStatus.unknown,
      },
      requiredCapabilities: capabilities is List
          ? capabilities.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  final WorkflowRuntimeStatus status;
  final List<String> requiredCapabilities;
}

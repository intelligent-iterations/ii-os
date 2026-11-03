import '../models/github_setup_readiness.dart';
import '../models/production_line.dart';
import '../repositories/production_line_repository.dart';
import '../repositories/workshop_repository.dart';
import '../services/api_client.dart';

/// The production lines the signed-in member may see, plus the health the
/// sidebar badges them with.
///
/// Split out of `AppController` because it is self-contained: the shell needs
/// the list to draw the rail, and nothing else in the app depends on it.
final class ProductionLineDirectory {
  ProductionLineDirectory(ApiClient api)
    : repository = ProductionLineApiRepository(api),
      _workshop = WorkshopApiRepository(api);

  final ProductionLineRepository repository;
  final WorkshopRepository _workshop;

  /// Server-filtered: an Editor is sent only the lines they belong to, so this
  /// is the access boundary's result rather than a display convenience.
  List<ProductionLineModel> lines = const [];

  GitHubSetupReadinessModel? _readiness;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  void clear() {
    lines = const [];
    _readiness = null;
  }

  /// Reloads the lines and, when there are any, the readiness behind their
  /// badges.
  ///
  /// Failure leaves the section empty rather than breaking the shell: nothing
  /// else depends on lines existing, and a workspace with none is the normal
  /// starting state.
  Future<void> refresh(String? workspaceId, {required bool canRead}) async {
    if (workspaceId == null || !canRead) {
      clear();
      return;
    }
    try {
      lines = await repository.list(workspaceId);
    } on Object {
      lines = const [];
    }
    if (lines.isEmpty) return;
    // One readiness read covers every repository, so the sidebar can badge
    // each line without a request per line.
    _readiness = await _workshop.readiness(workspaceId);
  }

  /// Why [line] needs attention, or null when it is healthy or unknown.
  ///
  /// Unknown is deliberately silent: a badge raised because a check could not
  /// run would fire on every transient error and stop meaning anything.
  String? attentionFor(ProductionLineModel line) {
    final readiness = _readiness;
    if (readiness == null || readiness.readyFor(line.repository)) return null;
    if (!readiness.workspace.ready) {
      return 'The human-started deployment queue is not running for this '
          'workspace.';
    }
    final health = readiness.healthFor(line.repository);
    if (health == null) return null;
    return health.blockers.isEmpty ? health.label : health.blockers.first.label;
  }
}

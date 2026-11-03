import 'package:stacked/stacked.dart';

import '../models/agent_usage.dart';
import '../repositories/agent_usage_repository.dart';

final class AgentUsageViewModel extends BaseViewModel {
  AgentUsageViewModel({
    required this.workspaceId,
    required this.loader,
    required this.days,
    required this.origin,
    this.onFilterChanged,
  });

  final String workspaceId;
  final AgentUsageLoader loader;
  final void Function(int days, AgentExecutionOrigin origin)? onFilterChanged;

  int days;
  AgentExecutionOrigin origin;
  AgentUsageReport? report;
  String? errorMessage;
  int _loadGeneration = 0;

  Future<void> start() => load();

  Future<void> load({int? days, AgentExecutionOrigin? origin}) async {
    final generation = ++_loadGeneration;
    this.days = days ?? this.days;
    this.origin = origin ?? this.origin;
    errorMessage = null;
    setBusy(true);
    try {
      final next = await loader(
        workspaceId: workspaceId,
        days: this.days,
        origin: this.origin,
      );
      if (generation == _loadGeneration) report = next;
    } on Object catch (error) {
      if (generation == _loadGeneration) errorMessage = error.toString();
    } finally {
      if (generation == _loadGeneration) setBusy(false);
    }
  }

  void changeFilters(int days, AgentExecutionOrigin origin) {
    final callback = onFilterChanged;
    if (callback != null) {
      callback(days, origin);
      return;
    }
    load(days: days, origin: origin);
  }
}

import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/workflow_catalog_repository.dart';

final class WorkflowCatalogViewModel extends BaseViewModel {
  WorkflowCatalogViewModel({
    required this.workspaceId,
    required this.repository,
  });

  final String workspaceId;
  final WorkflowCatalogRepository repository;

  List<WorkflowTemplateModel> templates = const [];
  List<WorkflowCatalogIssue> issues = const [];
  String? errorMessage;
  bool loaded = false;
  bool refreshing = false;

  Future<void> start() async {
    errorMessage = null;
    setBusy(true);
    try {
      _apply(await repository.load(workspaceId));
    } on Object {
      errorMessage =
          'Workflows could not be loaded. Retry discovery in a moment.';
    } finally {
      loaded = true;
      setBusy(false);
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    errorMessage = null;
    notifyListeners();
    try {
      _apply(await repository.refresh(workspaceId));
    } on Object {
      errorMessage =
          'Workflow discovery could not finish. Check repository access and retry.';
    } finally {
      refreshing = false;
      loaded = true;
      notifyListeners();
    }
  }

  void _apply(WorkflowCatalogSnapshot snapshot) {
    templates = snapshot.templates;
    issues = snapshot.issues;
    notifyListeners();
  }
}

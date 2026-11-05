import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/workflow_template_repository.dart';

/// The catalog family the classification surface runs.
const classificationWorkflowIdPrefix = 'classification-';

/// Whether the classification tool can be offered, as the server reports it.
///
/// `checking` and `unconfirmed` are distinct from `notInstalled`: before the
/// answer arrives, or when the runner report is stale, the surface must not
/// claim the runtime is missing. `checkedOnRun` is offered without a claim
/// either way: the deployment reports no runner capacity, so the run itself
/// checks for the model.
enum ClassificationAvailability {
  checking,
  available,
  notInstalled,
  unconfirmed,
  notConfigured,
  checkedOnRun,
}

ClassificationAvailability classificationAvailabilityOf(
  List<WorkflowTemplateModel> templates,
) {
  final template = resolveSelectedTemplate(templates);
  if (template == null) return ClassificationAvailability.notConfigured;
  return switch (template.runtime?.status) {
    WorkflowRuntimeStatus.available => ClassificationAvailability.available,
    WorkflowRuntimeStatus.unavailable =>
      ClassificationAvailability.notInstalled,
    WorkflowRuntimeStatus.notReported =>
      ClassificationAvailability.checkedOnRun,
    WorkflowRuntimeStatus.unknown ||
    null => ClassificationAvailability.unconfirmed,
  };
}

/// The Playground host: the Ghost-mode choice shared by every tab, and the one
/// server fact the tab bar needs before any tab is opened.
final class PlaygroundViewModel extends BaseViewModel {
  PlaygroundViewModel({required this._templates, required this.workspaceId});

  final WorkflowTemplateRepository _templates;
  final String workspaceId;

  bool ghostMode = false;
  ClassificationAvailability classification =
      ClassificationAvailability.checking;

  /// Reads the template list once per Playground visit; no recurring read.
  Future<void> load() async {
    try {
      classification = classificationAvailabilityOf(
        await _templates.list(
          workspaceId,
          workflowIdPrefix: classificationWorkflowIdPrefix,
        ),
      );
    } on Object {
      classification = ClassificationAvailability.unconfirmed;
    }
    notifyListeners();
  }

  void setGhostMode(bool value) {
    if (ghostMode == value) return;
    ghostMode = value;
    notifyListeners();
  }
}

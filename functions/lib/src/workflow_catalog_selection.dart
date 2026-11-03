import 'workflow_catalog.dart';
import 'workflow_catalog_store.dart';

/// Whether the workspace's explicit selection authorizes [workflow].
///
/// Catalog entries with a `model` input are model choices for one dispatch
/// workflow, not separate execution capabilities. Approving one therefore
/// approves its sibling models on the exact same repository and workflow path.
/// Entries for other operations remain independently selected even when a
/// repository implements them in the same wrapper file.
bool workspaceWorkflowSelectionIncludes({
  required WorkflowCatalog catalog,
  required Set<String> selectedWorkflowKeys,
  required WorkflowDefinition workflow,
}) {
  if (selectedWorkflowKeys.contains(
    workflowKey(catalog.repository, workflow.id),
  )) {
    return true;
  }
  if (!workflow.inputs.containsKey('model')) return false;
  return catalog.workflows.any(
    (candidate) =>
        candidate.inputs.containsKey('model') &&
        candidate.dispatchWorkflow == workflow.dispatchWorkflow &&
        selectedWorkflowKeys.contains(
          workflowKey(catalog.repository, candidate.id),
        ),
  );
}

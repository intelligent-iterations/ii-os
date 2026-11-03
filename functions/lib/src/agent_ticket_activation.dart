import 'api_error.dart';
import 'ticket_content.dart';
import 'workshop_status_transition.dart';

final class AgentTicketActivationTarget {
  const AgentTicketActivationTarget({
    required this.projectId,
    required this.itemId,
    required this.repository,
    required this.repositoryId,
    required this.issueNumber,
    required this.title,
    required this.issueUrl,
    required this.issueState,
    required this.status,
    required this.statusFieldId,
    required this.todoOptionId,
    required this.inProgressOptionId,
    required this.ticket,
  });

  factory AgentTicketActivationTarget.fromProject({
    required String projectId,
    required String itemId,
    required Map<String, Object?> project,
    String? expectedRepository,
  }) {
    if (expectedRepository != null && project['id'] != projectId) {
      throw const ApiError(
        409,
        'agent_project_mismatch',
        'The returned Project does not match the selected Project.',
      );
    }
    Map<String, Object?>? statusField;
    for (final field in _nodes(project['fields'])) {
      if (field['__typename'] == 'ProjectV2SingleSelectField' &&
          field['name'] == 'Status') {
        statusField = field;
        break;
      }
    }
    final statusFieldId = statusField?['id'] as String? ?? '';
    var todoOptionId = '';
    var inProgressOptionId = '';
    final options = statusField?['options'];
    if (options is List<Object?>) {
      for (final option in options.whereType<Map<String, Object?>>()) {
        if (option['name'] == 'Todo') {
          todoOptionId = option['id'] as String? ?? '';
        } else if (option['name'] == 'In Progress') {
          inProgressOptionId = option['id'] as String? ?? '';
        }
      }
    }
    if (statusFieldId.isEmpty ||
        todoOptionId.isEmpty ||
        inProgressOptionId.isEmpty) {
      throw const ApiError(
        409,
        'agent_project_status_invalid',
        'The Project requires Status options Todo and In Progress.',
      );
    }

    Map<String, Object?>? item;
    for (final candidate in _nodes(project['items'])) {
      if (candidate['id'] == itemId) {
        item = candidate;
        break;
      }
    }
    final content = item?['content'];
    if (item == null || content is! Map<String, Object?>) {
      throw const ApiError(
        404,
        'agent_ticket_not_found',
        'The Project ticket could not be found.',
      );
    }
    if (item['isArchived'] == true) {
      throw const ApiError(
        409,
        'agent_ticket_archived',
        'Restore the Project item before using this ticket.',
      );
    }
    final repository = content['repository'];
    final repositoryName = repository is Map<String, Object?>
        ? repository['nameWithOwner'] as String? ?? ''
        : '';
    final repositoryId = repository is Map<String, Object?>
        ? (repository['databaseId'] as num?)?.toInt() ?? 0
        : 0;
    if (expectedRepository != null && repositoryName != expectedRepository) {
      throw const ApiError(
        409,
        'agent_ticket_repository_mismatch',
        'The Project ticket does not belong to the selected repository.',
      );
    }
    final issueNumber = (content['number'] as num?)?.toInt() ?? 0;
    if (content['__typename'] != 'Issue' ||
        repositoryName.isEmpty ||
        repositoryId <= 0 ||
        issueNumber <= 0) {
      throw const ApiError(
        422,
        'agent_ticket_invalid',
        'Only repository issues can be activated for an agent.',
      );
    }
    var status = '';
    for (final value in _nodes(item['fieldValues'])) {
      final field = value['field'];
      if (field is Map<String, Object?> && field['id'] == statusFieldId) {
        status = value['name'] as String? ?? '';
        break;
      }
    }
    return AgentTicketActivationTarget(
      projectId: projectId,
      itemId: itemId,
      repository: repositoryName,
      repositoryId: repositoryId,
      issueNumber: issueNumber,
      title: content['title'] as String? ?? '',
      issueUrl: content['url'] as String? ?? '',
      issueState: content['state'] as String? ?? '',
      status: status,
      statusFieldId: statusFieldId,
      todoOptionId: todoOptionId,
      inProgressOptionId: inProgressOptionId,
      ticket: TicketContent.parse(content['body']),
    );
  }

  final String projectId;
  final String itemId;
  final String repository;
  final int repositoryId;
  final int issueNumber;
  final String title;
  final String issueUrl;
  final String issueState;
  final String status;
  final String statusFieldId;
  final String todoOptionId;
  final String inProgressOptionId;
  final TicketContent ticket;

  bool get needsHumanResponse => status == 'Needs Human Input';
  bool get canDeploy => workshopStatusCanDeploy(status);

  void validateActivation({
    bool allowRecovery = false,
    String dispatchStatus = '',
  }) {
    if (issueState != 'OPEN') {
      throw const ApiError(
        409,
        'agent_ticket_closed',
        'Reopen the issue before deploying it.',
      );
    }
    if (status != 'Todo' &&
        !(allowRecovery &&
            workshopStatusCanDeploy(status, dispatchStatus: dispatchStatus))) {
      throw const ApiError(
        409,
        'agent_ticket_not_todo',
        'This ticket changed after Workshop loaded. Refresh it and use the available action.',
      );
    }
    if (!ticket.structured ||
        ticket.definitionOfDone.isEmpty ||
        ticket.howToTest.isEmpty) {
      throw const ApiError(
        422,
        'agent_ticket_requirements_incomplete',
        'Definition of Done and How to test are required before deployment.',
      );
    }
    if (ticket.permissionProfile == 'none') {
      throw const ApiError(
        422,
        'agent_ticket_permissions_required',
        'Select an agent permission profile before deployment.',
      );
    }
    if (ticket.permissionRef != 'dev') {
      throw const ApiError(
        422,
        'agent_permission_ref_unreviewed',
        'Agent permission profiles must be approved on dev.',
      );
    }
  }
}

List<Map<String, Object?>> _nodes(Object? connection) {
  if (connection is! Map<String, Object?>) return const [];
  final nodes = connection['nodes'];
  return nodes is List<Object?>
      ? nodes.whereType<Map<String, Object?>>().toList()
      : const [];
}

bool agentActivationRequiresResponse(
  Map<String, Object?> activation, {
  String? currentTicketBodyDigest,
}) {
  if (activation['status'] == 'reset') return false;
  if (activation['finalProjectStatus'] != 'needs_human_input') return false;
  if (currentTicketBodyDigest == null || currentTicketBodyDigest.isEmpty) {
    return true;
  }
  final approvedDigest = activation['ticketBodyDigest'];
  return approvedDigest is! String ||
      approvedDigest.isEmpty ||
      approvedDigest == currentTicketBodyDigest;
}

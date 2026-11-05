import 'api_error.dart';
import 'provider_contracts/agent_execution.dart';
import 'ticket_content.dart';

const _activeAgentDispatchStatuses = {
  ...agentExecutionLiveStatuses,
  'dispatching',
  'dispatched',
  'dispatched_unconfirmed',
  'workflow_dispatching',
  'workflow_bound',
  'workflow_unconfirmed',
  'fleet_submitting',
  'fleet_queued',
  'fleet_running',
  'fleet_cleaning',
  'fleet_cleaned',
};

bool ticketDeletionRequiresPausedAgent(Object? status) =>
    status is String && _activeAgentDispatchStatuses.contains(status);

final class TicketDeletionTarget {
  const TicketDeletionTarget({
    required this.itemId,
    required this.repository,
    required this.issueNumber,
    required this.issueOpen,
    required this.content,
  });

  factory TicketDeletionTarget.fromProject({
    required String projectId,
    required String itemId,
    required String repository,
    required int issueNumber,
    required Map<String, Object?> project,
  }) {
    if (project['id'] != projectId) {
      throw const ApiError(
        404,
        'project_not_found',
        'The configured GitHub Project could not be found.',
      );
    }
    final items = project['items'];
    final nodes = items is Map<String, Object?> ? items['nodes'] : null;
    final matchingItems = nodes is List<Object?>
        ? nodes
              .whereType<Map<String, Object?>>()
              .where((item) => item['id'] == itemId)
              .toList()
        : const <Map<String, Object?>>[];
    if (matchingItems.length != 1) {
      throw const ApiError(
        404,
        'ticket_not_in_project',
        'This ticket is no longer in the selected Workshop Project.',
      );
    }
    final issue = matchingItems.single['content'];
    final issueRepository = issue is Map<String, Object?>
        ? issue['repository']
        : null;
    final nameWithOwner = issueRepository is Map<String, Object?>
        ? issueRepository['nameWithOwner']
        : null;
    final number = issue is Map<String, Object?>
        ? (issue['number'] as num?)?.toInt()
        : null;
    if (issue is! Map<String, Object?> ||
        issue['__typename'] != 'Issue' ||
        nameWithOwner != repository ||
        number != issueNumber) {
      throw const ApiError(
        409,
        'ticket_changed',
        'The Workshop ticket changed. Refresh it before deleting.',
      );
    }
    final content = TicketContent.parse(issue['body']);
    if (content.agentReady) {
      throw const ApiError(
        409,
        'ticket_agent_active',
        'Cancel the deployment before deleting this ticket.',
      );
    }
    return TicketDeletionTarget(
      itemId: itemId,
      repository: repository,
      issueNumber: issueNumber,
      issueOpen: issue['state']?.toString().toUpperCase() == 'OPEN',
      content: content,
    );
  }

  final String itemId;
  final String repository;
  final int issueNumber;
  final bool issueOpen;
  final TicketContent content;
}

part of 'api.dart';

extension on IiOsApi {
  Future<Map<String, Map<String, Object?>>> _agentDispatchStates(
    String workspaceId,
    List<String> projectItemIds,
  ) async {
    if (projectItemIds.isEmpty) return const {};
    final workspace = store.firestore.collection('workspaces').doc(workspaceId);
    final snapshots = await Future.wait([
      store.firestore.getAll([
        for (final itemId in projectItemIds)
          workspace.collection('agentDispatches').doc(itemId),
      ]),
      store.firestore.getAll([
        for (final itemId in projectItemIds)
          workspace.collection('agentActivations').doc(itemId),
      ]),
    ]);
    final result = <String, Map<String, Object?>>{};
    final activationItemIds = <String>{};
    for (final snapshot in snapshots[0]) {
      final data = snapshot.data();
      if (data == null) continue;
      result[snapshot.ref.id] = {
        'status': data['status'],
        'failureCode': data['failureCode'],
        'detail': data['detail'],
        'workflowRunId': data['workflowRunId'],
        'workflowRunUrl': data['workflowRunUrl'],
        'workflowBoundAt': data['workflowBoundAt'],
        'fleetJobId': data['fleetJobId'],
        'executionId': data['executionId'],
        'executionRunningAt': _agentDispatchDate(data['executionRunningAt']),
        'stateUpdatedAt': _agentDispatchDate(data['updatedAt']),
        'fleetRunningAt': _agentDispatchDate(data['fleetRunningAt']),
        'dispatchedAt': _agentDispatchDate(data['dispatchedAt']),
        'finalOutcome': data['finalOutcome'],
        'finalProjectStatus': data['finalProjectStatus'],
        'finalEffectsPublished': data['finalEffectsPublished'],
        'finalPullRequestUrl': data['finalPullRequestUrl'],
      };
    }
    for (final snapshot in snapshots[1]) {
      final activation = snapshot.data();
      if (activation == null) continue;
      activationItemIds.add(snapshot.ref.id);
      result[snapshot.ref.id] = cohesiveAgentDispatchState(
        result[snapshot.ref.id] ?? const {},
        activation,
      );
    }
    for (final entry in result.entries.toList(growable: false)) {
      if (activationItemIds.contains(entry.key)) continue;
      result[entry.key] = cohesiveAgentDispatchState(entry.value, const {});
    }
    return result;
  }
}

const int workshopProjectItemReadLimit = 100;

/// Returns the exact item ids whose receipt state may appear on this board.
///
/// GitHub's board query requests one page of at most 100 items. Refusing an
/// oversized or malformed response keeps Firestore reads bounded before they
/// execute and prevents stale receipt history from entering the projection.
List<String> workshopProjectItemIds(Map<String, Object?> project) {
  final items = _workshopConnectionNodes(project['items']);
  if (items.length > workshopProjectItemReadLimit) {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned too many Project items to load safely.',
    );
  }
  return {
    for (final item in items)
      if (item['id'] case final String id when id.isNotEmpty) id,
  }.toList(growable: false);
}

String? _agentDispatchDate(Object? value) =>
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : null;

Map<String, Object?> cohesiveAgentDispatchState(
  Map<String, Object?> dispatch,
  Map<String, Object?> activation, {
  DateTime? now,
}) {
  final evaluatedAt = (now ?? DateTime.now()).toUtc();
  final activationStatus = activation['status'];
  if (activationStatus == 'reset' || activationStatus == 'resetting') {
    return {
      'status': activationStatus,
      'activationStatus': activationStatus,
      'receiptAllowsDeploy': activationStatus == 'reset',
      'receiptAllowsReset': true,
    };
  }
  var currentStatus = dispatch['status'];
  currentStatus =
      agentDispatchRecoveryStatus(dispatch, activation, evaluatedAt) ??
      currentStatus;
  final invalidatedWhileQueued =
      activationStatus == 'invalidated' &&
      (currentStatus == null ||
          currentStatus == 'queued' ||
          currentStatus == 'dispatch_failed');
  final resetAllowed = agentTicketResetAllowed(
    activation,
    dispatch,
    evaluatedAt,
  );
  return {
    ...dispatch,
    'status': ?currentStatus,
    if (invalidatedWhileQueued) ...{
      'status': 'approval_invalidated',
      'failureCode': 'agent_approval_invalidated',
      'detail': agentApprovalInvalidatedDetail,
    },
    'activationStatus': activationStatus,
    'workflowBoundAt': _agentDispatchDate(
      activation['workflowBoundAt'] ?? dispatch['workflowBoundAt'],
    ),
    'finalOutcome': activation['finalOutcome'],
    'finalProjectStatus': activation['finalProjectStatus'],
    // The activation is the immutable receipt, so it wins over the mutable
    // dispatch mirror when both carry an outcome.
    'finalPullRequestUrl':
        activation['finalPullRequestUrl'] ?? dispatch['finalPullRequestUrl'],
    'permissionProfile': activation['permissionProfile'],
    'permissionVersion': activation['permissionVersion'],
    // The approved brief digest binds any finalized result to the exact
    // ticket content that produced it. It is consumed by the board projection
    // below and is never sent to the browser directly.
    'ticketBodyDigest': activation['ticketBodyDigest'],
    'receiptAllowsDeploy':
        resetAllowed && !agentPickupInFlight(activation, dispatch, evaluatedAt),
    'receiptAllowsReset': resetAllowed,
  };
}

Map<String, Map<String, Object?>> withWorkshopDeployability(
  Map<String, Object?> project,
  Map<String, Map<String, Object?>> dispatches,
) {
  final result = {
    for (final entry in dispatches.entries)
      entry.key: Map<String, Object?>.from(entry.value),
  };
  final fields = _workshopConnectionNodes(project['fields']);
  final statusField = fields
      .where(
        (field) =>
            field['__typename'] == 'ProjectV2SingleSelectField' &&
            field['name'] == 'Status',
      )
      .firstOrNull;
  final options = statusField?['options'];
  final optionNames = options is List<Object?>
      ? options
            .whereType<Map<String, Object?>>()
            .map((option) => option['name'])
            .whereType<String>()
            .toSet()
      : const <String>{};
  final statusFieldId = optionNames.containsAll(const {'Todo', 'In Progress'})
      ? (statusField?['id'] as String? ?? '')
      : '';

  for (final item in _workshopConnectionNodes(project['items'])) {
    final itemId = item['id'] as String? ?? '';
    if (itemId.isEmpty) continue;
    var status = '';
    if (statusFieldId.isNotEmpty) {
      for (final value in _workshopConnectionNodes(item['fieldValues'])) {
        final field = value['field'];
        if (field is Map<String, Object?> && field['id'] == statusFieldId) {
          status = value['name'] as String? ?? '';
          break;
        }
      }
    }
    final dispatch = result[itemId] ?? const <String, Object?>{};
    final content = item['content'];
    final issueOpen =
        content is Map<String, Object?> && content['state'] == 'OPEN';
    final hasSupersededReceipt =
        dispatches.containsKey(itemId) && dispatch['status'] != 'reset';
    final approvedDigest = dispatch['ticketBodyDigest'];
    final currentDigest = content is Map<String, Object?>
        ? ticketBodyDigest(TicketContent.parse(content['body']))
        : null;
    final resultMatchesCurrentTicket =
        approvedDigest is String &&
        approvedDigest.isNotEmpty &&
        approvedDigest == currentDigest;
    result[itemId] = {
      for (final entry in dispatch.entries)
        if (entry.key != 'ticketBodyDigest') entry.key: entry.value,
      'resultMatchesCurrentTicket': resultMatchesCurrentTicket,
      'canDeploy':
          statusFieldId.isNotEmpty &&
          dispatch['receiptAllowsDeploy'] != false &&
          workshopStatusCanDeploy(
            status,
            dispatchStatus: dispatch['status'] as String? ?? '',
          ),
      'canReset':
          issueOpen &&
          item['isArchived'] != true &&
          dispatch['receiptAllowsReset'] != false &&
          (status.isNotEmpty || hasSupersededReceipt),
    };
  }
  return result;
}

List<Map<String, Object?>> _workshopConnectionNodes(Object? connection) {
  if (connection is! Map<String, Object?>) return const [];
  final nodes = connection['nodes'];
  return nodes is List<Object?>
      ? nodes.whereType<Map<String, Object?>>().toList()
      : const [];
}

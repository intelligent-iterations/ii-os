import '../models/agent_permission.dart';
import '../models/github_setup_readiness.dart';
import '../models/models.dart';
import '../models/workshop_ticket.dart';
import '../models/workshop_room.dart';
import '../models/workshop_pull_request.dart';
import '../services/api_client.dart';

/// Everything one production line needs to render its board in a single read.
final class WorkshopBoardModel {
  const WorkshopBoardModel({
    required this.tickets,
    required this.statusFieldId,
    required this.statusOptions,
    required this.supportsTodo,
    required this.profiles,
    required this.profilesVerified,
    this.readiness,
    this.advisory,
  });

  final List<WorkshopTicket> tickets;

  /// The Project's Status field, needed to write a status back. Empty when the
  /// board has no Status field at all.
  final String statusFieldId;

  /// The GitHub Project's Status options.
  ///
  /// Left in transport shape because `WorkshopTicketDetail` already takes it
  /// that way; typing it would mean changing a shared widget, and its golden,
  /// for no behaviour change.
  final List<JsonMap> statusOptions;

  /// Whether the Project has the human-controlled `Todo` option that agent
  /// deployment is gated on.
  final bool supportsTodo;

  final List<AgentPermissionModel> profiles;

  /// True only when the current board load successfully read permission
  /// profiles. An empty verified list means absent; false means unknown.
  final bool profilesVerified;
  final GitHubSetupReadinessModel? readiness;

  /// Set when part of the board loaded but a secondary read failed.
  ///
  /// Permissions and readiness are degraded information, not a dead board: a
  /// failure there must not blank the tickets an operator came to look at.
  final String? advisory;
}

/// The single owner of the reads behind a production line's board.
abstract interface class WorkshopRepository {
  /// Loads the board for one repository within one GitHub Project.
  Future<WorkshopBoardModel> board({
    required String workspaceId,
    required String projectId,
    required String repository,
  });

  /// Reads agent readiness for every repository in the workspace at once.
  ///
  /// One call covers every production line, which is what lets the sidebar
  /// badge each of them without a request per line.
  Future<GitHubSetupReadinessModel?> readiness(String workspaceId);

  /// Sets the human-controlled Project status for one ticket.
  Future<void> setStatus({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    required String fieldId,
    required String optionId,
  });

  /// Freezes and dispatches one exact human-approved Workshop pass.
  Future<void> deploy({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    String response = '',
  });

  /// Returns one inactive ticket to its freshly filed Workshop state.
  Future<void> reset({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
  });

  /// Saves the reviewed model/profile choice before live readiness is rerun.
  Future<void> selectProfile({
    required String workspaceId,
    required WorkshopTicket ticket,
    required String permissionProfile,
    required String permissionRef,
  });

  Future<WorkshopPullRequestModel> pullRequest({
    required String workspaceId,
    required String itemId,
  });

  Future<WorkshopPullRequestModel> approveAndMergePullRequest({
    required String workspaceId,
    required String itemId,
    required String expectedHeadSha,
  });
}

abstract interface class WorkshopRoomRepository {
  Future<void> saveRooms(String workspaceId, List<WorkshopRoomModel> rooms);
}

final class WorkshopApiRepository
    implements WorkshopRepository, WorkshopRoomRepository {
  const WorkshopApiRepository(this._api);

  final ApiClient _api;

  @override
  Future<WorkshopBoardModel> board({
    required String workspaceId,
    required String projectId,
    required String repository,
  }) async {
    final response = await _api.get(
      'v1/workspaces/$workspaceId/projects',
      query: {'projectId': projectId, 'repository': repository},
    );
    final project = asJsonMap(response['project']);
    final dispatches = asJsonMap(
      response['agentDispatches'],
    ).map((key, value) => MapEntry(key, asJsonMap(value)));

    final statusField = workshopNodes(asJsonMap(project['fields'])['nodes'])
        .where(
          (field) =>
              field['__typename'] == 'ProjectV2SingleSelectField' &&
              (field['name'] as String? ?? '').toLowerCase() == 'status',
        )
        .firstOrNull;
    final statusOptions = workshopNodes(statusField?['options']);
    final tickets = workshopNodes(asJsonMap(project['items'])['nodes'])
        .where((item) => asJsonMap(item['content'])['__typename'] == 'Issue')
        .map(
          (item) => WorkshopTicket.fromProjectItem(
            item,
            statusFieldId: statusField?['id'] as String? ?? '',
            agentDispatch: dispatches[item['id'] as String? ?? ''] ?? const {},
          ),
        )
        .where((ticket) => ticket.repository == repository)
        .toList();

    var advisories = <String>[];
    var profiles = const <AgentPermissionModel>[];
    var profilesVerified = false;
    try {
      final response = await _api.get(
        'v1/workspaces/$workspaceId/agent-permissions',
        query: {'repository': repository, 'ref': 'dev'},
      );
      profiles = (response['profiles'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .map(AgentPermissionModel.fromJson)
          .toList();
      profilesVerified = true;
    } on Object catch (error) {
      advisories.add('Permission profiles could not be verified: $error');
    }

    GitHubSetupReadinessModel? readiness;
    try {
      readiness = GitHubSetupReadinessModel.fromJson(
        await _api.get(
          'v1/workspaces/$workspaceId/agent-readiness',
          query: {'repository': repository},
        ),
      );
    } on Object catch (error) {
      advisories.add('Agent readiness could not be verified: $error');
    }

    return WorkshopBoardModel(
      tickets: tickets,
      statusFieldId: statusField?['id'] as String? ?? '',
      statusOptions: statusOptions,
      supportsTodo: statusOptions.any((option) => option['name'] == 'Todo'),
      profiles: profiles,
      profilesVerified: profilesVerified,
      readiness: readiness,
      advisory: advisories.isEmpty ? null : advisories.join(' '),
    );
  }

  @override
  Future<GitHubSetupReadinessModel?> readiness(String workspaceId) async {
    try {
      return GitHubSetupReadinessModel.fromJson(
        await _api.get('v1/workspaces/$workspaceId/agent-readiness'),
      );
    } on Object {
      // Unknown is not unhealthy. A badge raised on a failed check would cry
      // wolf on every transient error, so the caller shows nothing instead.
      return null;
    }
  }

  @override
  Future<void> setStatus({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    required String fieldId,
    required String optionId,
  }) => _api.patch(
    'v1/workspaces/$workspaceId/projects/items/$itemId',
    body: {
      'projectId': projectId,
      'repository': ?repository,
      'fieldId': fieldId,
      'value': {'singleSelectOptionId': optionId},
    },
  );

  @override
  Future<void> deploy({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
    String response = '',
  }) => _api.patch(
    'v1/workspaces/$workspaceId/projects/items/$itemId/agent-activation',
    body: {
      'projectId': projectId,
      'repository': ?repository,
      'ready': true,
      if (response.isNotEmpty) 'response': response,
    },
  );

  @override
  Future<void> reset({
    String? repository,
    required String workspaceId,
    required String projectId,
    required String itemId,
  }) => _api.patch(
    'v1/workspaces/$workspaceId/projects/items/$itemId/reset',
    body: {'projectId': projectId, 'repository': ?repository},
  );

  @override
  Future<void> selectProfile({
    required String workspaceId,
    required WorkshopTicket ticket,
    required String permissionProfile,
    required String permissionRef,
  }) => _api.patch(
    'v1/workspaces/$workspaceId/tickets/${ticket.number}',
    body: {
      'repository': ticket.repository,
      'title': ticket.title,
      'definitionOfDone': ticket.definitionOfDone,
      'howToTest': ticket.howToTest,
      'permissions': {'profile': permissionProfile, 'ref': permissionRef},
      'context': ticket.context,
      'state': ticket.issueOpen ? 'open' : 'closed',
    },
  );

  @override
  Future<WorkshopPullRequestModel> pullRequest({
    required String workspaceId,
    required String itemId,
  }) async {
    final response = await _api.get(
      'v1/workspaces/$workspaceId/projects/items/$itemId/pull-request',
    );
    return WorkshopPullRequestModel.fromJson(
      asJsonMap(response['pullRequest']),
    );
  }

  @override
  Future<WorkshopPullRequestModel> approveAndMergePullRequest({
    required String workspaceId,
    required String itemId,
    required String expectedHeadSha,
  }) async {
    final response = await _api.post(
      'v1/workspaces/$workspaceId/projects/items/$itemId/pull-request/merge',
      body: {'expectedHeadSha': expectedHeadSha},
    );
    return WorkshopPullRequestModel.fromJson(asJsonMap(response['data']));
  }

  @override
  Future<void> saveRooms(String workspaceId, List<WorkshopRoomModel> rooms) =>
      _api.patch(
        'v1/workspaces/$workspaceId',
        body: {'workshopRooms': rooms.map((room) => room.toJson()).toList()},
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

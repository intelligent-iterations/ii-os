import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character.dart';
import '../models/data_plane_connection.dart';
import '../models/models.dart';
import '../repositories/media_repository.dart';
import '../repositories/organization_repository.dart';
import 'production_line_directory.dart';
import 'workshop_ticket_draft_session.dart';
import '../services/api_client.dart';
import '../services/artifact_read_url_cache.dart';
import '../services/verified_artifact_media.dart';
import '../services/workshop_session_cache.dart';

part 'app_controller_organizations.dart';

final class AppController extends ChangeNotifier {
  AppController({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;
  late final MediaRepository media = MediaRepository(api: api);
  late final OrganizationRepository organizations = OrganizationRepository(api);
  late final ProductionLineDirectory productionLines = ProductionLineDirectory(
    api,
  );
  final workshopTicketDrafts = WorkshopTicketDraftSession();
  final workshopSessions = WorkshopSessionCache();

  DataPlaneConnectionModel? connection;
  DataPlaneValidationModel? connectionValidation;
  SessionModel? session;
  WorkspaceAccess? selectedAccess;
  JsonMap dashboard = const {};
  bool loading = true;
  bool refreshing = false;
  bool connectionBusy = false;
  bool openWorkspaceResourceSelection = false;
  String? errorMessage;

  WorkspaceModel? get workspace => selectedAccess?.workspace;
  MembershipModel? get membership => selectedAccess?.membership;

  bool can(String capability) => membership?.can(capability) ?? false;

  Future<ArtifactReadGrant> readArtifactUrl({
    required String workspaceId,
    required String jobId,
    required JsonMap artifact,
  }) async {
    final expectedBucket = _artifactBucket(workspaceId);
    return media.readArtifactUrl(
      workspaceId: workspaceId,
      jobId: jobId,
      expectedBucket: expectedBucket,
      artifact: artifact,
    );
  }

  Future<VerifiedArtifactMedia> readVerifiedArtifact({
    required String workspaceId,
    required String jobId,
    required JsonMap artifact,
    bool transient = false,
  }) async {
    final expectedBucket = _artifactBucket(workspaceId);
    return media.readVerifiedArtifact(
      workspaceId: workspaceId,
      jobId: jobId,
      expectedBucket: expectedBucket,
      artifact: artifact,
      transient: transient,
    );
  }

  Future<VerifiedArtifactMedia> readCharacterImage(
    CharacterImageModel image,
  ) async {
    final workspaceId = workspace?.id ?? '';
    final expectedBucket = _artifactBucket(workspaceId);
    final expiresAt = image.readUrlExpiresAt;
    final isSource = image.jobId.startsWith('source-asset:');
    final expectedPrefix = isSource
        ? 'workspaces/$workspaceId/'
        : 'workspaces/$workspaceId/runs/${image.jobId}/';
    if (!image.hasReadGrant ||
        image.workspaceId != workspaceId ||
        image.bucket != expectedBucket ||
        !image.path.startsWith(expectedPrefix) ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc()) ||
        !const {
          'image/jpeg',
          'image/png',
          'image/webp',
        }.contains(image.contentType)) {
      throw const FormatException(
        'The character sheet authorization is unavailable.',
      );
    }
    final expected = ArtifactAuthorizationIdentity(
      workspaceId: workspaceId,
      jobId: image.jobId,
      bucket: expectedBucket,
      objectName: image.path,
      generation: image.generation,
      sizeBytes: image.sizeBytes,
      sha256: image.sha256,
      contentType: image.contentType,
    );
    return media.readGrantedArtifact(
      expected: expected,
      grant: ArtifactReadGrant(
        url: image.readUrl,
        expiresAt: expiresAt,
        workspaceId: image.workspaceId,
        jobId: image.jobId,
        bucket: image.bucket,
        objectName: image.path,
        generation: image.generation,
        sizeBytes: image.sizeBytes,
        sha256: image.sha256,
        contentType: image.contentType,
      ),
    );
  }

  String _artifactBucket(String workspaceId) {
    final activeConnection = connection;
    final resolvedConnection = session?.connectionForWorkspace(workspaceId);
    final connectionIsAuthorized = resolvedConnection != null
        ? activeConnection?.matches(resolvedConnection) == true
        : activeConnection?.isBoundTo(
                workspaceId: workspaceId,
                organizationId: workspace?.organizationId ?? '',
              ) ==
              true;
    if (workspaceId.isEmpty ||
        workspace?.id != workspaceId ||
        activeConnection == null ||
        !connectionIsAuthorized ||
        activeConnection.bucket.isEmpty) {
      throw const FormatException(
        'The workspace media connection is unavailable.',
      );
    }
    return activeConnection.bucket;
  }

  Future<void> initialize({String? preferredWorkspaceId}) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _retireLegacyConnectionState();
      await _loadSession(preferredWorkspaceId: preferredWorkspaceId);
      await refreshDashboard();
      await _refreshProductionLines();
    } on Object catch (error) {
      errorMessage = _message(error);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final selectedId = workspace?.id;
      await _loadSession(preferredWorkspaceId: selectedId);
      await refreshDashboard();
      await _refreshProductionLines();
    } on Object catch (error) {
      errorMessage = _message(error);
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> selectWorkspace(String workspaceId) async {
    final access = session?.workspaces
        .where((item) => item.workspace.id == workspaceId)
        .firstOrNull;
    if (access == null) return;
    media.clear();
    workshopSessions.clear();
    selectedAccess = access;
    _syncWorkspaceConnection();
    dashboard = const {};
    productionLines.clear();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('ii_os_workspace_id', workspaceId);
    await refreshDashboard();
    await _refreshProductionLines();
    notifyListeners();
  }

  Future<void> _refreshProductionLines() =>
      productionLines.refresh(workspace?.id, canRead: can('lines.read'));

  Future<void> refreshDashboard() async {
    final workspaceId = workspace?.id;
    if (workspaceId == null) {
      dashboard = const {};
      return;
    }
    dashboard = await api.get('v1/workspaces/$workspaceId/dashboard');
  }

  void _notifyWorkspaceCreated() => notifyListeners();

  Future<void> leaveCurrentWorkspace() async {
    final workspaceId = workspace?.id;
    if (workspaceId == null) return;
    media.clear();
    workshopSessions.clear();
    await api.delete('v1/workspaces/$workspaceId/members/me');
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('ii_os_workspace_id');
    await _loadSession();
    await refreshDashboard();
    notifyListeners();
  }

  Future<void> deleteCurrentWorkspace() async {
    final workspaceId = workspace?.id;
    if (workspaceId == null) return;
    media.clear();
    workshopSessions.clear();
    await api.delete('v1/workspaces/$workspaceId');
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('ii_os_workspace_id');
    await _loadSession();
    await refreshDashboard();
    notifyListeners();
  }

  Future<List<JsonMap>> listAvailableInvitations() async {
    final response = await api.get('v1/invitations');
    return (response['invitations'] as List<Object?>? ?? const [])
        .map(asJsonMap)
        .toList();
  }

  Future<void> acceptInvitation(String invitationId) async {
    final response = await api.post('v1/invitations/$invitationId/accept');
    await _applyAcceptedInvitation(response);
  }

  Future<void> _applyAcceptedInvitation(JsonMap response) async {
    final workspaceId = asJsonMap(response['data'])['workspaceId'] as String?;
    await _loadSession(preferredWorkspaceId: workspaceId);
    if (workspaceId != null && workspaceId.isNotEmpty) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('ii_os_workspace_id', workspaceId);
    }
    await refreshDashboard();
    notifyListeners();
  }

  Future<DataPlaneValidationModel> _validateDataPlane(
    DataPlaneConnectionModel candidate,
  ) async {
    return _connectionOperation(() async {
      final workspaceId = workspace?.id;
      final organizationId = workspace?.organizationId ?? '';
      if (workspaceId == null) {
        throw const ApiFailure(
          'workspace_required',
          'Create or join a workspace before connecting GCP.',
        );
      }
      if (!candidate.isBoundTo(
        workspaceId: workspaceId,
        organizationId: organizationId,
      )) {
        throw const ApiFailure(
          'workspace_connection_mismatch',
          'This connection belongs to a different ii-os tenant.',
        );
      }
      final route = candidate.isOrganizationBound
          ? 'v1/organizations/$organizationId/connection/validate'
          : 'v1/workspaces/$workspaceId/connection/validate';
      final validation = DataPlaneValidationModel.fromJson(
        asJsonMap(
          (await api.post(route, body: candidate.validationBody()))['data'],
        ),
      );
      connectionValidation = validation;
      if (!validation.ready) return validation;
      await _loadSession(preferredWorkspaceId: workspaceId);
      connectionValidation = validation;
      await refreshDashboard();
      errorMessage = null;
      return validation;
    });
  }

  Future<DataPlaneValidationModel> revalidateDataPlane() async {
    final current = connection;
    if (current == null) {
      throw const ApiFailure(
        'data_plane_required',
        'Connect a GCP data plane first.',
      );
    }
    return _validateDataPlane(current);
  }

  Future<T> _connectionOperation<T>(Future<T> Function() operation) async {
    if (connectionBusy) {
      throw const ApiFailure(
        'connection_busy',
        'A connection check is already running.',
      );
    }
    connectionBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await operation();
    } on Object catch (error) {
      errorMessage = _message(error);
      rethrow;
    } finally {
      connectionBusy = false;
      notifyListeners();
    }
  }

  Future<void> _loadSession({String? preferredWorkspaceId}) async {
    final json = await api.get('v1/session');
    await _applySession(json, preferredWorkspaceId: preferredWorkspaceId);
  }

  Future<void> _retireLegacyConnectionState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('ii_os_data_plane_connection_v1');
  }

  Future<void> _applySession(
    JsonMap json, {
    String? preferredWorkspaceId,
  }) async {
    session = SessionModel.fromJson(json);
    final preferences = await SharedPreferences.getInstance();
    final stored =
        preferredWorkspaceId ?? preferences.getString('ii_os_workspace_id');
    final workspaces = session!.workspaces;
    selectedAccess = workspaces.isEmpty
        ? null
        : workspaces.firstWhere(
            (item) => item.workspace.id == stored,
            orElse: () => workspaces.first,
          );
    _syncWorkspaceConnection();
  }

  void _syncWorkspaceConnection() {
    connection = session?.connectionForWorkspace(selectedAccess?.workspace.id);
    connectionValidation = null;
  }

  @override
  void dispose() {
    media.dispose();
    api.close();
    super.dispose();
  }
}

String _message(Object error) => switch (error) {
  ApiFailure() => error.message,
  FormatException(:final message) => message.toString(),
  TimeoutException() =>
    'The ii-os control API did not respond in time. Try again.',
  _ => 'The request could not be completed.',
};

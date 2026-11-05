import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'agent_activation_store.dart';
import 'agent_permission_approval_store.dart';
import 'agent_permission_profile.dart';
import 'agent_repository_health.dart';
import 'agent_repository_topology.dart';
import 'agent_ticket_activation.dart';
import 'agent_ticket_dispatcher.dart';
import 'agent_usage_key_store.dart';
import 'agent_usage_store.dart';
import 'agent_workflow_recovery.dart';
import 'api_error.dart';
import 'asset_retention_service.dart';
import 'asset_url_signer.dart';
import 'audit_sink.dart';
import 'auth_service.dart';
import 'bug_report_service.dart';
import 'character_generation.dart';
import 'character_reference_sheet.dart';
import 'character_store.dart';
import 'client_error_rate_limiter.dart';
import 'connected_data_api.dart';
import 'creative_surface.dart';
import 'data_plane_connection.dart';
import 'data_plane_connection_validator.dart';
import 'domain.dart';
import 'error_reporter.dart';
import 'fleet_reporting_key_store.dart';
import 'fleet_runner_discovery.dart';
import 'fleet_snapshot.dart';
import 'fleet_snapshot_store.dart';
import 'gcp_bootstrap.dart';
import 'ghost_generation_service.dart';
import 'github_client.dart';
import 'github_workflow_coordinator.dart';
import 'http_support.dart';
import 'interactive_session_coordinator.dart';
import 'job_run_store.dart';
import 'notification_store.dart';
import 'organization.dart';
import 'organization_invitation_store.dart';
import 'organization_people_store.dart';
import 'organization_resource_store.dart';
import 'organization_resources.dart';
import 'organization_store.dart';
import 'passwordless_auth_service.dart';
import 'production_line_store.dart';
import 'prompt_enhancement_key_store.dart';
import 'prompt_enhancer.dart';
import 'prompt_guide_catalog.dart';
import 'prompt_guide_store.dart';
import 'providers/firebase/organization_deletion_repository.dart';
import 'providers/firebase/organization_member_repository.dart';
import 'read_cost_policy.dart';
import 'requested_prompt_enhancement_bypass.dart';
import 'retention_policy.dart';
import 'storyboard_panel_extend_store.dart';
import 'storyboard_panel_image_store.dart';
import 'storyboard_references.dart';
import 'storyboard_store.dart';
import 'ticket_content.dart';
import 'ticket_deletion_target.dart';
import 'video_project_store.dart';
import 'workflow_api.dart';
import 'workflow_catalog_store.dart';
import 'workshop_status_transition.dart';
import 'workspace_invitation.dart';
import 'workspace_prompt_enhancement.dart';
import 'workspace_repository_selection.dart';
import 'workspace_resource_grant_store.dart';
import 'workspace_resource_grants.dart';
import 'workspace_store.dart';

part 'api_agent_permission_routes.dart';
part 'api_agent_dispatch_state.dart';
part 'api_agent_readiness_route.dart';
part 'api_bug_report_route.dart';
part 'api_github_setup_route.dart';
part 'api_agent_ticket_activation_route.dart';
part 'api_agent_ticket_reset_route.dart';
part 'api_agent_usage_key_routes.dart';
part 'api_agent_usage_route.dart';
part 'api_audit_support.dart';
part 'api_character_generation_routes.dart';
part 'api_character_routes.dart';
part 'api_codex_auth_route.dart';
part 'api_error_support.dart';
part 'api_fleet_routes.dart';
part 'api_job_route.dart';
part 'api_interactive_session_routes.dart';
part 'api_notification_routes.dart';
part 'api_organization_routes.dart';
part 'api_organization_resource_routes.dart';
part 'api_people_routes.dart';
part 'api_passwordless_auth_routes.dart';
part 'api_production_line_routes.dart';
part 'api_pull_request_routes.dart';
part 'api_prompt_enhancement_route.dart';
part 'api_prompt_guide_routes.dart';
part 'api_storyboard_animation_route.dart';
part 'api_storyboard_extend_route.dart';
part 'api_storyboard_routes.dart';
part 'api_workshop_status.dart';
part 'api_video_project_routes.dart';
part 'api_workspace_resource_routes.dart';

final class IiOsApi {
  IiOsApi({
    required this.auth,
    required this.store,
    required this.characters,
    required this.assetRetention,
    required this.audit,
    required this.agentUsage,
    required this.agentUsageKeys,
    required this.fleetSnapshots,
    required this.fleetReportingKeys,
    required this.promptEnhancer,
    required this.promptEnhancementKeys,
    required this.promptGuides,
    required this.githubForWorkspace,
    required this.workflows,
    required this.workflowApi,
    required this.connectedDataApi,
    required this.notifications,
    required this.organizations,
    required this.organizationInvitations,
    required this.passwordlessAuth,
    required this.webOrigin,
    required this.agentRepositories,
    required this.agentEngines,
    BugReportService? bugReports,
    ErrorReporter? errors,
    ClientErrorRateLimiter? clientErrorRateLimiter,
    this.interactiveSessions,
  }) : bugReports = bugReports ?? BugReportService(store: store),
       errors = errors ?? ErrorReporter(environment: 'unknown'),
       clientErrorRateLimiter =
           clientErrorRateLimiter ?? ClientErrorRateLimiter();

  final AuthService auth;
  final WorkspaceStore store;
  final CharacterStore characters;
  final AssetRetentionService assetRetention;
  final AuditSink audit;
  final AgentUsageStore agentUsage;
  final AgentUsageKeyStore agentUsageKeys;
  final FleetSnapshotStore fleetSnapshots;
  final FleetReportingKeyStore fleetReportingKeys;
  final DeepSeekPromptEnhancer promptEnhancer;
  final PromptEnhancementKeyStore promptEnhancementKeys;
  final PromptGuideStore promptGuides;
  final GitHubClientProvider githubForWorkspace;
  final GitHubWorkflowCoordinator workflows;
  final WorkflowApi workflowApi;
  final ConnectedDataApi connectedDataApi;
  final NotificationStore notifications;
  final OrganizationStore organizations;
  final OrganizationInvitationStore organizationInvitations;
  final PasswordlessAuthService passwordlessAuth;
  final String webOrigin;
  final AgentRepositoryTopology agentRepositories;
  final AgentEngineCatalog agentEngines;
  final BugReportService bugReports;
  final ErrorReporter errors;
  final ClientErrorRateLimiter clientErrorRateLimiter;
  final InteractiveSessionCoordinator? interactiveSessions;
  final Uuid _uuid = const Uuid();

  Future<Response> handle(Request request) async {
    final requestId = _requestId(request);
    var path = <String>[];
    AuthenticatedUser? actor;
    try {
      final routedPath = request.url.queryParameters['route'];
      path = routedPath == null
          ? request.url.pathSegments.where((part) => part.isNotEmpty).toList()
          : routedPath.split('/').where((part) => part.isNotEmpty).toList();
      if (path.isNotEmpty && path.first == 'api') {
        path.removeAt(0);
      }
      if (request.method == 'GET' && _matches(path, ['v1', 'health'])) {
        return jsonResponse(200, {
          'status': 'ok',
          'service': 'ii-os',
        }, requestId: requestId);
      }

      if (workflowApi.isWorkflowRoute(path)) {
        return await workflowApi.handleWorkflow(request, requestId, path);
      }

      final passwordlessResponse = await _passwordlessAuthRoute(
        request,
        requestId,
        path,
      );
      if (passwordlessResponse != null) return passwordlessResponse;

      if (_isAgentUsageIngestRoute(path) &&
          agentUsageKeys.requestCarriesUsageKey(request)) {
        return await _agentUsageKeyIngestRoute(request, requestId, path);
      }

      if (_isFleetIngestRoute(path) &&
          fleetReportingKeys.requestCarriesFleetKey(request)) {
        return await _fleetIngestRoute(request, requestId, path);
      }

      final authenticatedActor = await auth.authenticate(request);
      actor = authenticatedActor;
      requireExplicitReadPolicyForRead(request, path);
      if (request.method == 'POST' && _matches(path, ['v1', 'client-errors'])) {
        return await _clientErrorRoute(request, requestId, authenticatedActor);
      }
      final notificationResponse = await _notificationRoute(
        request,
        requestId,
        authenticatedActor,
        path,
      );
      if (notificationResponse != null) return notificationResponse;
      final connectedData = await connectedDataApi.handleAuthenticated(
        request,
        requestId,
        path,
        authenticatedActor,
      );
      if (connectedData != null) return connectedData;
      if (request.method == 'GET' && _matches(path, ['v1', 'session'])) {
        final access = await store.listWorkspaceAccess(authenticatedActor);
        final tenants = await organizations.listOrganizationAccess(
          authenticatedActor,
        );
        return jsonResponse(200, {
          'user': authenticatedActor.toJson(),
          'workspaces': access,
          'organizations': tenants,
        }, requestId: requestId);
      }
      if (request.method == 'GET' && _matches(path, ['v1', 'invitations'])) {
        return jsonResponse(200, {
          'invitations': await store.listAvailableInvites(authenticatedActor),
        }, requestId: requestId);
      }
      if (request.method == 'POST' &&
          path.length == 4 &&
          path[0] == 'v1' &&
          path[1] == 'invitations' &&
          path[3] == 'accept') {
        final invitationId = _validatedInviteId(path[2]);
        return await _audited(
          requestId: requestId,
          actor: authenticatedActor,
          action: 'invitation.accept',
          targetType: 'workspace_invitation',
          targetId: invitationId,
          execute: () async {
            final membership = await store.acceptInviteById(
              invitationId,
              authenticatedActor,
            );
            return membership.toJson();
          },
        );
      }
      if (request.method == 'POST' && _matches(path, ['v1', 'workspaces'])) {
        final body = await readJsonObject(request);
        final name = requiredString(body, 'name', maxLength: 100);
        final environment = body['environment'] as String? ?? 'dev';
        if (!const {'dev', 'prod'}.contains(environment)) {
          throw const ApiError(
            400,
            'invalid_environment',
            'Environment must be dev or prod.',
          );
        }
        final requestedOrganizationId = body['organizationId'] as String? ?? '';
        return await _audited(
          requestId: requestId,
          actor: authenticatedActor,
          action: 'workspace.create',
          targetType: 'workspace',
          metadata: {
            'environment': environment,
            if (requestedOrganizationId.isNotEmpty)
              'organizationId': requestedOrganizationId,
          },
          execute: () async {
            final organizationActor = requestedOrganizationId.isEmpty
                ? await organizations.createOrganization(
                    name: body['organizationName'] as String? ?? name,
                    actor: authenticatedActor,
                  )
                : await _requireOrganization(
                    authenticatedActor,
                    requestedOrganizationId,
                    OrganizationCapability.workspacesCreate,
                  );
            final workspace = await store.createWorkspace(
              organizationId: organizationActor.organizationId,
              organizationActor: organizationActor,
              name: name,
              environment: environment,
            );
            return workspace.toJson();
          },
        );
      }
      // Before the organization route so a fleet path is never consumed by the
      // generic tenant matcher above it.
      final fleetResponse = await _fleetRoute(
        request,
        requestId,
        authenticatedActor,
        path,
      );
      if (fleetResponse != null) return fleetResponse;
      final organizationResponse = await _organizationRoute(
        request,
        requestId,
        authenticatedActor,
        path,
      );
      if (organizationResponse != null) return organizationResponse;
      if (path.length >= 3 && path[0] == 'v1' && path[1] == 'workspaces') {
        return await _workspaceRoute(
          request,
          requestId,
          authenticatedActor,
          path,
        );
      }
      throw const ApiError(404, 'not_found', 'API route not found.');
    } on ApiError catch (error, stackTrace) {
      await _reportApiError(error, stackTrace, request, path, requestId, actor);
      return jsonResponse(error.status, {
        'error': {
          'code': error.code,
          'message': error.message,
          if (error.details != null) 'details': error.details,
        },
      }, requestId: requestId);
    } on FormatException catch (error) {
      return jsonResponse(400, {
        'error': {'code': 'invalid_request', 'message': error.message},
      }, requestId: requestId);
    } catch (error, stackTrace) {
      await _reportUnhandledRequestError(
        error,
        stackTrace,
        request,
        path,
        requestId,
        actor,
      );
      return jsonResponse(500, {
        'error': {
          'code': 'internal_error',
          'message': 'The request could not be completed.',
        },
      }, requestId: requestId);
    }
  }

  Future<Response> _workspaceRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    List<String> path,
  ) async {
    final workspaceId = path[2];
    final interactiveResponse = await _interactiveSessionRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (interactiveResponse != null) return interactiveResponse;
    final resourceResponse = await _workspaceResourceRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (resourceResponse != null) return resourceResponse;
    if (path.length == 3 && request.method == 'GET') {
      final membership = await store.requireAccess(
        actor,
        workspaceId,
        Capability.workspaceRead,
      );
      final workspace = await store.getWorkspace(workspaceId);
      return jsonResponse(200, {
        'workspace': workspace.toJson(),
        'membership': membership.toJson(),
      }, requestId: requestId);
    }
    if (path.length == 3 && request.method == 'PATCH') {
      final access = await store.requireAccessContext(
        actor,
        workspaceId,
        Capability.workspaceManage,
      );
      final body = {...await readJsonObject(request)};
      final organizationId = access.workspace.organizationId;
      if (access.workspace.resourceGrantsExplicit &&
          (body.containsKey('repositories') ||
              body.containsKey('githubInstallationId'))) {
        throw const ApiError(
          409,
          'workspace_resource_grants_required',
          'Change inherited GitHub access through workspace resource grants.',
        );
      }
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'workspace.update',
        targetType: 'workspace',
        targetId: workspaceId,
        execute: () async {
          final requestedRepositories =
              organizationId.isNotEmpty && body.containsKey('repositories')
              ? validatedWorkspaceStrings(body['repositories'], 'repositories')
              : null;
          if (requestedRepositories != null) {
            body['repositories'] = requestedRepositories;
            final boundary = await organizations.repositoryBoundary(
              organizationId,
            );
            if (boundary.declared) {
              final additions = requestedRepositories.toSet().difference(
                boundary.repositories,
              );
              if (additions.isNotEmpty) {
                await _requireOrganization(
                  actor,
                  organizationId,
                  OrganizationCapability.credentialsManage,
                );
                await organizations.addRepositories(organizationId, additions);
              }
            }
          }
          if (organizationId.isNotEmpty &&
              body.containsKey('githubInstallationId')) {
            final rawInstallationId = body.remove('githubInstallationId');
            if (rawInstallationId != null &&
                (rawInstallationId is! num || rawInstallationId.toInt() <= 0)) {
              throw const ApiError(
                400,
                'invalid_installation',
                'GitHub installation ID must be a positive integer.',
              );
            }
            final installationId = rawInstallationId == null
                ? null
                : (rawInstallationId as num).toInt();
            if (installationId != access.workspace.githubInstallationId) {
              await _requireOrganization(
                actor,
                organizationId,
                OrganizationCapability.credentialsManage,
              );
              await organizations.saveGithubInstallationId(
                organizationId,
                installationId,
              );
            }
          }
          return (await store.updateWorkspace(
            workspaceId,
            await _withStoredPromptEnhancementKey(workspaceId, actor, body),
          )).toJson();
        },
      );
    }
    if (path.length == 3 && request.method == 'DELETE') {
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'workspace.delete',
        targetType: 'workspace',
        targetId: workspaceId,
        execute: () async {
          await store.deleteWorkspace(workspaceId: workspaceId, actor: actor);
          return {'workspaceId': workspaceId};
        },
      );
    }
    final promptEnhancementResponse = await _promptEnhancementRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (promptEnhancementResponse != null) return promptEnhancementResponse;
    final promptGuideResponse = await _workspacePromptGuideRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (promptGuideResponse != null) return promptGuideResponse;
    if (path.length == 4 && path[3] == 'dashboard' && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.workspaceRead);
      final workspace = await store.getWorkspace(workspaceId);
      final kpis = await store.dashboard(workspaceId);
      return jsonResponse(200, {
        ...kpis,
        'repositories': workspace.repositories.length,
        'projects': workspace.projects.length,
        'workflows': workspace.workflows.length,
      }, requestId: requestId);
    }
    final peopleResponse = await _peopleRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (peopleResponse != null) return peopleResponse;
    if (path.length >= 4 && path[3] == 'tickets') {
      return await _ticketRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 && path[3] == 'agent-permissions') {
      return await _agentPermissionRoute(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    final agentUsageKeyResponse = await _agentUsageKeyRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (agentUsageKeyResponse != null) return agentUsageKeyResponse;
    final agentUsageResponse = await _agentUsageRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (agentUsageResponse != null) return agentUsageResponse;
    if (path.length >= 4 && path[3] == 'production-lines') {
      return await _productionLineRoute(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    final githubSetupResponse = await _githubSetupRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (githubSetupResponse != null) return githubSetupResponse;
    final agentReadinessResponse = await _agentReadinessRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (agentReadinessResponse != null) return agentReadinessResponse;
    final codexAuthResponse = await _codexAuthRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (codexAuthResponse != null) return codexAuthResponse;
    if (path.length == 4 &&
        path[3] == 'github-projects' &&
        request.method == 'GET') {
      final context = await store.requireAccessContext(
        actor,
        workspaceId,
        Capability.workspaceManage,
      );
      final repository = request.url.queryParameters['repository']?.trim();
      if (repository == null || repository.isEmpty || repository.length > 200) {
        throw const ApiError(
          400,
          'repository_required',
          'Choose a workspace repository.',
        );
      }
      final github = await githubForWorkspace(context.workspace);
      final projects = await github.listLinkedProjects(
        context.workspace,
        repository,
      );
      return jsonResponse(200, {'projects': projects}, requestId: requestId);
    }
    if (path.length >= 4 && path[3] == 'projects') {
      return await _projectRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 &&
        (path[3] == 'characters' || path[3] == 'character')) {
      return _characterRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 && path[3] == 'video-projects') {
      return _videoProjectRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 && path[3] == 'storyboards') {
      return _storyboardRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 && path[3] == 'bug-reports') {
      return _bugReportRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 && path[3] == 'source-assets') {
      return workflowApi.handleSourceAsset(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    if (path.length >= 4 && path[3] == 'jobs') {
      return await _jobRoute(request, requestId, actor, workspaceId, path);
    }
    if (path.length >= 4 && path[3] == 'workflow-tokens') {
      return workflowApi.handleAdmin(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    if (path.length == 5 &&
        path[3] == 'workflow-catalogs' &&
        path[4] == 'refresh' &&
        request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.workspaceManage);
      final workspace = await store.getWorkspace(workspaceId);
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'github_workflow_catalog.refresh',
        targetType: 'github_workflow_catalog',
        metadata: {'repositories': workspace.repositories.length},
        execute: () => workflows.refreshCatalogs(workspace),
      );
    }
    if (path.length == 4 &&
        path[3] == 'workflow-templates' &&
        request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final workspace = await store.getWorkspace(workspaceId);
      return jsonResponse(200, {
        'templates': await workflows.listTemplates(workspace),
      }, requestId: requestId);
    }
    throw const ApiError(404, 'not_found', 'Workspace route not found.');
  }

  Future<Response> _ticketRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.ticketsRead);
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final repository = request.url.queryParameters['repository'];
      if (repository == null) {
        throw const ApiError(
          400,
          'repository_required',
          'Select a repository.',
        );
      }
      final issues = await github.listIssues(workspace, repository);
      return jsonResponse(200, {'issues': issues}, requestId: requestId);
    }
    if (path.length == 4 && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.ticketsWrite);
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final body = await readJsonObject(request);
      final repository = requiredString(body, 'repository', maxLength: 200);
      final title = requiredString(body, 'title', maxLength: 256);
      final ticketContent = TicketContent.fromRequest({
        ...body,
        'agent': {'ready': false},
      });
      final projectId = body['projectId'];
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'ticket.create',
        targetType: 'github_issue',
        metadata: {'repository': repository, 'projectId': projectId},
        execute: () => github.createIssue(
          workspace,
          repository: repository,
          title: title,
          body: ticketContent.toMarkdown(),
          projectId: projectId is String && projectId.isNotEmpty
              ? projectId
              : null,
        ),
      );
    }
    if (path.length == 5 && request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.ticketsWrite);
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final number = int.tryParse(path[4]);
      if (number == null || number <= 0) {
        throw const ApiError(
          400,
          'invalid_issue_number',
          'Issue number is invalid.',
        );
      }
      final body = await readJsonObject(request);
      final repository = requiredString(body, 'repository', maxLength: 200);
      final ticketContent = TicketContent.fromRequest({
        ...body,
        'agent': {'ready': false},
      });
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'ticket.update',
        targetType: 'github_issue',
        targetId: '$repository#$number',
        metadata: {'repository': repository, 'number': number},
        execute: () => github.updateIssue(
          workspace,
          repository: repository,
          number: number,
          title: body['title'] as String?,
          body: ticketContent.toMarkdown(),
          state: body['state'] as String?,
        ),
      );
    }
    if (path.length == 5 && request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.ticketsWrite);
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final number = int.tryParse(path[4]);
      if (number == null || number <= 0) {
        throw const ApiError(
          400,
          'invalid_issue_number',
          'Issue number is invalid.',
        );
      }
      final body = await readJsonObject(request);
      final repository = requiredString(body, 'repository', maxLength: 200);
      final projectId = requiredString(body, 'projectId', maxLength: 200);
      final itemId = requiredString(body, 'itemId', maxLength: 200);
      final dispatchState = await _agentDispatchState(workspaceId, itemId);
      if (ticketDeletionRequiresPausedAgent(dispatchState['status'])) {
        throw const ApiError(
          409,
          'ticket_agent_active',
          'Cancel the deployment or wait for the agent to finish before deleting this ticket.',
        );
      }
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'ticket.delete',
        targetType: 'github_issue',
        targetId: '$repository#$number',
        metadata: {
          'repository': repository,
          'number': number,
          'projectId': projectId,
          'itemId': itemId,
        },
        execute: () => github.removeWorkshopTicket(
          workspace,
          repository: repository,
          issueNumber: number,
          projectId: projectId,
          itemId: itemId,
        ),
      );
    }
    throw const ApiError(404, 'not_found', 'Ticket route not found.');
  }

  Future<Response> _projectRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    final pullRequestResponse = await _pullRequestRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (pullRequestResponse != null) return pullRequestResponse;
    final activationResponse = await _agentTicketActivationRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (activationResponse != null) return activationResponse;
    final resetResponse = await _agentTicketResetRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (resetResponse != null) return resetResponse;
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.ticketsRead);
      final workspace = await store.getWorkspace(workspaceId);
      final selectedRepository = selectedWorkspaceRepository(
        workspace,
        request.url.queryParameters['repository'],
      );
      final github = await githubForWorkspace(workspace);
      final projectId = request.url.queryParameters['projectId'];
      if (projectId == null) {
        throw const ApiError(
          400,
          'project_required',
          'Select a GitHub Project.',
        );
      }
      final project = await github.getProject(
        workspace,
        projectId,
        repository: selectedRepository,
      );
      final dispatches = await _agentDispatchStates(
        workspaceId,
        workshopProjectItemIds(project),
      );
      return jsonResponse(200, {
        'project': project,
        'agentDispatches': withWorkshopDeployability(project, dispatches),
      }, requestId: requestId);
    }
    if (path.length == 6 && path[4] == 'items' && request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.ticketsWrite);
      final workspace = await store.getWorkspace(workspaceId);
      final body = await readJsonObject(request);
      final rawValue = body['value'];
      if (rawValue is! Map<String, Object?>) {
        throw const ApiError(
          400,
          'invalid_field_value',
          'Project field value is invalid.',
        );
      }
      final projectId = requiredString(body, 'projectId', maxLength: 200);
      final fieldId = requiredString(body, 'fieldId', maxLength: 200);
      final selectedRepository = selectedWorkspaceRepository(
        workspace,
        body['repository'],
      );
      final github = await githubForWorkspace(workspace);
      final project = await github.getProject(
        workspace,
        projectId,
        repository: selectedRepository,
      );
      requireSelectedProjectItemRepository(
        project: project,
        projectId: projectId,
        itemId: path[5],
        repository: selectedRepository,
      );
      final transition = _workshopStatusTransition(
        project: project,
        itemId: path[5],
        fieldId: fieldId,
        value: rawValue,
      );
      if (transition != null) {
        final dispatch = await _agentDispatchState(workspaceId, path[5]);
        var deployedAgentPullRequest = false;
        var resultMatchesCurrentTicket = false;
        if (const {
              'Todo',
              'In Progress',
              'Needs Human Input',
            }.contains(transition.$1) &&
            transition.$2 == 'Ready for QA') {
          final identity = await _recordedAgentPullRequest(
            workspaceId,
            path[5],
            workspace,
          );
          final pullRequest = await github.getPullRequestWithQaDeployment(
            workspace,
            repository: identity.$1,
            number: identity.$2,
          );
          requireSuccessfulQaDeployment(pullRequest);
          deployedAgentPullRequest = true;
          final target = AgentTicketActivationTarget.fromProject(
            projectId: projectId,
            itemId: path[5],
            project: project,
          );
          resultMatchesCurrentTicket =
              identity.$3 == ticketBodyDigest(target.ticket);
        }
        requireHumanWorkshopStatusTransition(
          current: transition.$1,
          target: transition.$2,
          dispatchStatus: dispatch['status'] as String? ?? '',
          deployedAgentPullRequest: deployedAgentPullRequest,
          resultMatchesCurrentTicket: resultMatchesCurrentTicket,
        );
      }
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'project_item.field.update',
        targetType: 'github_project_item',
        targetId: path[5],
        metadata: {
          'projectId': projectId,
          'fieldId': fieldId,
          if (transition != null) 'fromStatus': transition.$1,
          if (transition != null) 'toStatus': transition.$2,
        },
        execute: () => github.updateProjectItemField(
          workspace,
          repository: selectedRepository,
          projectId: projectId,
          itemId: path[5],
          fieldId: fieldId,
          value: rawValue,
        ),
      );
    }
    if (path.length == 6 && path[4] == 'fields' && request.method == 'PATCH') {
      await store.requireAccess(
        actor,
        workspaceId,
        Capability.projectFieldsManage,
      );
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final body = await readJsonObject(request);
      final rawOptions = body['options'];
      if (rawOptions is! List<Object?>) {
        throw const ApiError(
          400,
          'invalid_status_options',
          'Status options are required.',
        );
      }
      final options = rawOptions.map((value) {
        if (value is! Map<String, Object?>) {
          throw const ApiError(
            400,
            'invalid_status_options',
            'A status option is invalid.',
          );
        }
        return value;
      }).toList();
      final projectId = requiredString(body, 'projectId', maxLength: 200);
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'project_field.options.update',
        targetType: 'github_project_field',
        targetId: path[5],
        metadata: {'projectId': projectId, 'optionCount': options.length},
        execute: () => github.updateProjectFieldOptions(
          workspace,
          projectId: projectId,
          fieldId: path[5],
          options: options,
        ),
      );
    }
    throw const ApiError(404, 'not_found', 'Project route not found.');
  }

  String _requestId(Request request) {
    final supplied = request.headers['x-request-id']?.trim() ?? '';
    if (RegExp(r'^[A-Za-z0-9_.:-]{8,64}$').hasMatch(supplied)) return supplied;
    return _uuid.v4();
  }
}

bool _matches(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

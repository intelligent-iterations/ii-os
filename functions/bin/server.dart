import 'dart:convert';
import 'dart:io';

import 'package:firebase_functions/firebase_functions.dart';
import 'package:googleapis/secretmanager/v1.dart' as secretmanager;
import 'package:googleapis_auth/auth_io.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';
import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/agent_repository_topology.dart';
import 'package:ii_os_functions/src/agent_trusted_source_manifest.dart';
import 'package:ii_os_functions/src/agent_usage_key_codec.dart';
import 'package:ii_os_functions/src/agent_usage_key_store.dart';
import 'package:ii_os_functions/src/agent_usage_store.dart';
import 'package:ii_os_functions/src/api.dart';
import 'package:ii_os_functions/src/asset_retention_service.dart';
import 'package:ii_os_functions/src/audit_sink.dart';
import 'package:ii_os_functions/src/auth_service.dart';
import 'package:ii_os_functions/src/character_store.dart';
import 'package:ii_os_functions/src/classification_runtime.dart';
import 'package:ii_os_functions/src/codex_auth_store.dart';
import 'package:ii_os_functions/src/connected_data_api.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/error_reporter.dart';
import 'package:ii_os_functions/src/fleet_reporting_key_codec.dart';
import 'package:ii_os_functions/src/fleet_reporting_key_store.dart';
import 'package:ii_os_functions/src/fleet_snapshot_store.dart';
import 'package:ii_os_functions/src/github_actions_oidc.dart';
import 'package:ii_os_functions/src/github_app_secret.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:ii_os_functions/src/github_qa_deployment_cache.dart';
import 'package:ii_os_functions/src/github_workflow_coordinator.dart';
import 'package:ii_os_functions/src/interactive_session_coordinator.dart';
import 'package:ii_os_functions/src/interactive_session_workspace_access.dart';
import 'package:ii_os_functions/src/notification_dispatcher.dart';
import 'package:ii_os_functions/src/notification_store.dart';
import 'package:ii_os_functions/src/organization_invitation_rate_limiter.dart';
import 'package:ii_os_functions/src/organization_invitation_store.dart';
import 'package:ii_os_functions/src/organization_store.dart';
import 'package:ii_os_functions/src/otp_email_sender.dart';
import 'package:ii_os_functions/src/passwordless_auth_codec.dart';
import 'package:ii_os_functions/src/passwordless_auth_service.dart';
import 'package:ii_os_functions/src/prompt_enhancement_key_codec.dart';
import 'package:ii_os_functions/src/prompt_enhancement_key_store.dart';
import 'package:ii_os_functions/src/prompt_enhancer.dart';
import 'package:ii_os_functions/src/prompt_guide_store.dart';
import 'package:ii_os_functions/src/providers/firebase/firebase_identity_provider.dart';
import 'package:ii_os_functions/src/providers/firebase/firestore_system_owner_repository.dart';
import 'package:ii_os_functions/src/providers/firebase/interactive_session_repository.dart';
import 'package:ii_os_functions/src/providers/gcp/bigquery_error_sink.dart';
import 'package:ii_os_functions/src/providers/gcp/gcs_artifact_storage_gateway.dart';
import 'package:ii_os_functions/src/providers/relay/http_session_relay_control.dart';
import 'package:ii_os_functions/src/source_asset_service.dart';
import 'package:ii_os_functions/src/transactional_mail.dart';
import 'package:ii_os_functions/src/workflow_api.dart';
import 'package:ii_os_functions/src/workflow_artifact_verifier.dart';
import 'package:ii_os_functions/src/workflow_run_broker.dart';
import 'package:ii_os_functions/src/workflow_token_codec.dart';
import 'package:ii_os_functions/src/workflow_token_store.dart';
import 'package:ii_os_functions/src/workspace_resource_resolver.dart';
import 'package:ii_os_functions/src/workspace_store.dart';

final bootstrapOwnerEmails = defineString(
  'II_OS_BOOTSTRAP_OWNER_EMAILS',
  const ParamOptions(defaultValue: ''),
);
final auditProjectId = defineString(
  'II_OS_AUDIT_PROJECT_ID',
  const ParamOptions(defaultValue: ''),
);
final auditDatasetId = defineString(
  'II_OS_AUDIT_DATASET_ID',
  const ParamOptions(defaultValue: ''),
);
final auditTableId = defineString(
  'II_OS_AUDIT_TABLE_ID',
  const ParamOptions(defaultValue: 'mutation_audit'),
);
final errorProjectId = defineString(
  'II_OS_ERROR_PROJECT_ID',
  const ParamOptions(defaultValue: ''),
);
final errorDatasetId = defineString(
  'II_OS_ERROR_DATASET_ID',
  const ParamOptions(defaultValue: ''),
);
final errorTableId = defineString(
  'II_OS_ERROR_TABLE_ID',
  const ParamOptions(defaultValue: 'error_events'),
);
final agentUsageProjectId = defineString(
  'II_OS_AGENT_USAGE_PROJECT_ID',
  const ParamOptions(defaultValue: ''),
);
final agentUsageDatasetId = defineString(
  'II_OS_AGENT_USAGE_DATASET_ID',
  const ParamOptions(defaultValue: ''),
);
final agentUsageTableId = defineString(
  'II_OS_AGENT_USAGE_TABLE_ID',
  const ParamOptions(defaultValue: 'agent_usage_daily'),
);
final firestoreDatabaseId = defineString(
  'II_OS_FIRESTORE_DATABASE_ID',
  const ParamOptions(defaultValue: '(default)'),
);
final functionServiceAccount = defineString(
  'II_OS_FUNCTION_SERVICE_ACCOUNT',
  const ParamOptions(defaultValue: ''),
);
final webOrigin = defineString(
  'II_OS_WEB_ORIGIN',
  const ParamOptions(defaultValue: ''),
);
final deploymentProfile = defineString(
  'II_OS_DEPLOYMENT_PROFILE',
  const ParamOptions(defaultValue: 'prod'),
);
final agentCoordinatorRepository = defineString(
  'II_OS_AGENT_COORDINATOR_REPOSITORY',
  const ParamOptions(defaultValue: ''),
);
final agentPublicationTargets = defineString(
  'II_OS_AGENT_PUBLICATION_TARGETS',
  const ParamOptions(defaultValue: ''),
);
final agentTrustedSourceManifestBase64 = defineString(
  'II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64',
  const ParamOptions(defaultValue: ''),
);
final runnerCapacityProvider = defineString(
  'II_OS_RUNNER_CAPACITY_PROVIDER',
  const ParamOptions(defaultValue: 'none'),
);
final localAgentEngines = defineString(
  'II_OS_LOCAL_AGENT_ENGINES_BASE64',
  const ParamOptions(defaultValue: ''),
);
final authEmailFromAddress = defineString(
  'II_OS_AUTH_EMAIL_FROM_ADDRESS',
  const ParamOptions(defaultValue: ''),
);
final interactiveRelayUrl = defineString(
  'II_OS_INTERACTIVE_RELAY_URL',
  const ParamOptions(defaultValue: ''),
);
final interactiveSessionImage = defineString(
  'II_OS_INTERACTIVE_SESSION_IMAGE',
  const ParamOptions(defaultValue: ''),
);
final interactiveGrantSigningKeySecretRef = defineString(
  'II_OS_INTERACTIVE_GRANT_SIGNING_KEY_SECRET_REF',
  const ParamOptions(defaultValue: ''),
);
final interactiveRelayControlSecretRef = defineString(
  'II_OS_INTERACTIVE_RELAY_CONTROL_SECRET_REF',
  const ParamOptions(defaultValue: ''),
);

// ignore: non_constant_identifier_names
final II_OS_WORKFLOW_TOKEN_PEPPER = defineSecret('II_OS_WORKFLOW_TOKEN_PEPPER');
// ignore: non_constant_identifier_names
final II_OS_PROMPT_ENHANCEMENT_KEY_ENCRYPTION_KEY = defineSecret(
  'II_OS_PROMPT_ENHANCEMENT_KEY_ENCRYPTION_KEY',
);
// ignore: non_constant_identifier_names
final II_OS_AUTH_OTP_PEPPER = defineSecret('II_OS_AUTH_OTP_PEPPER');
// ignore: non_constant_identifier_names
final II_OS_AGENT_USAGE_KEY_PEPPER = defineSecret(
  'II_OS_AGENT_USAGE_KEY_PEPPER',
);
// ignore: non_constant_identifier_names
final ZEPTOMAIL_API_KEY = defineSecret('ZEPTOMAIL_API_KEY');
Future<void> main(List<String> args) async {
  await runFunctions((firebase) {
    IiOsApi? api;
    firebase.https.onRequest(
      name: 'api',
      // Secret parameters are resolved by the Functions runtime.
      // ignore: non_const_argument_for_const_parameter
      options: HttpsOptions(
        cors: const Cors(['*']),
        concurrency: const Concurrency(40),
        invoker: const Invoker.public(),
        maxInstances: const Instances(6),
        serviceAccount: ServiceAccount.param(functionServiceAccount),
        timeoutSeconds: const TimeoutSeconds(60),
        secrets: [
          II_OS_WORKFLOW_TOKEN_PEPPER,
          II_OS_PROMPT_ENHANCEMENT_KEY_ENCRYPTION_KEY,
          II_OS_AUTH_OTP_PEPPER,
          II_OS_AGENT_USAGE_KEY_PEPPER,
          ZEPTOMAIL_API_KEY,
        ],
      ),
      (request) async {
        api ??= await _buildApi(firebase);
        return api!.handle(request);
      },
    );
  });
}

Future<IiOsApi> _buildApi(Firebase firebase) async {
  final databaseId = firestoreDatabaseId.value().trim();
  final firestore = firebase.adminApp.firestore(databaseId: databaseId);
  final runtimeProject = firebase.adminApp.projectId?.trim() ?? '';
  if (runtimeProject.isEmpty) {
    throw StateError('The ii-os control-plane project is required.');
  }
  final emulated =
      Platform.environment['FIRESTORE_EMULATOR_HOST']?.isNotEmpty == true;
  final profile = deploymentProfile.value().trim();
  if (!emulated && profile != 'dev' && profile != 'prod') {
    throw StateError('II_OS_DEPLOYMENT_PROFILE must be dev or prod.');
  }
  final origin = webOrigin.value().trim().isEmpty && emulated
      ? 'http://127.0.0.1:5002'
      : webOrigin.value().trim();
  final brokerServiceAccount = functionServiceAccount.value().trim();
  if (!emulated && brokerServiceAccount.isEmpty) {
    throw StateError('II_OS_FUNCTION_SERVICE_ACCOUNT is required.');
  }
  final senderAddress = authEmailFromAddress.value().trim();
  if (senderAddress.isEmpty) {
    throw StateError('II_OS_AUTH_EMAIL_FROM_ADDRESS is required.');
  }
  final agentRepositories = AgentRepositoryTopology.fromConfiguration(
    coordinatorRepository: agentCoordinatorRepository.value(),
    publicationTargets: agentPublicationTargets.value(),
  );
  final agentSourceManifest = AgentTrustedSourceManifest.fromBase64(
    agentTrustedSourceManifestBase64.value(),
  );
  // Empty offers Codex only; an invalid value stops startup by name.
  final agentEngines = AgentEngineCatalog.fromBase64(localAgentEngines.value());
  // fleet reads each organization's capacity report; none reads nothing and
  // leaves the model check to the workflow. An invalid value stops startup.
  final capacityProvider = parseRunnerCapacityProvider(
    runnerCapacityProvider.value(),
  );

  final store = WorkspaceStore(firestore, emulated: emulated);
  final githubQaDeploymentCache = GitHubQaDeploymentCache();
  Future<GitHubClient> githubForWorkspace(Workspace workspace) async {
    return _githubClientForWorkspace(
      store,
      workspace,
      emulated: emulated,
      qaDeploymentCache: githubQaDeploymentCache,
      agentSourceManifest: agentSourceManifest,
      agentEngines: agentEngines,
    );
  }

  final audit = AuditSink(
    projectId: auditProjectId.value(),
    datasetId: auditDatasetId.value(),
    tableId: auditTableId.value(),
  );
  final errorSink = BigQueryErrorSink(
    projectId: errorProjectId.value().trim(),
    datasetId: errorDatasetId.value().trim(),
    tableId: errorTableId.value().trim(),
  );
  final errors = ErrorReporter(
    environment: runtimeProject,
    sink: errorSink.isConfigured ? errorSink : null,
  );
  final tokenService = WorkflowTokenService(
    store: store,
    codec: WorkflowTokenCodec(pepper: II_OS_WORKFLOW_TOKEN_PEPPER.value()),
  );
  final agentUsageKeys = AgentUsageKeyStore(
    store: store,
    codec: AgentUsageKeyCodec(pepper: II_OS_AGENT_USAGE_KEY_PEPPER.value()),
  );
  final organizationStore = OrganizationStore(firestore, emulated: emulated);
  final authCodec = PasswordlessAuthCodec(
    pepper: II_OS_AUTH_OTP_PEPPER.value(),
  );
  final fleetSnapshots = FleetSnapshotStore(organizations: organizationStore);
  final fleetReportingKeys = FleetReportingKeyStore(
    organizations: organizationStore,
    codec: FleetReportingKeyCodec(),
  );
  final codexAuth = CodexAuthStore(store: store);
  final artifactVerifier = WorkflowArtifactVerifier(
    GcsArtifactStorageGatewayResolver(store),
  );
  final promptEnhancementKeys = PromptEnhancementKeyStore(
    firestore: firestore,
    codec: PromptEnhancementKeyCodec(
      encryptionKey: II_OS_PROMPT_ENHANCEMENT_KEY_ENCRYPTION_KEY.value(),
      legacyPepper: II_OS_WORKFLOW_TOKEN_PEPPER.value(),
    ),
  );
  final promptEnhancer = DeepSeekPromptEnhancer(
    storedKeyReader: promptEnhancementKeys.read,
  );
  final sourceAssets = SourceAssetService(store: store);
  final assetRetention = AssetRetentionService(store: store);
  final notificationStore = NotificationStore(firestore);
  final promptGuides = PromptGuideStore(firestore: firestore);
  final workflowCoordinator = GitHubWorkflowCoordinator(
    githubForWorkspace: githubForWorkspace,
    store: store,
    classificationRuntime: classificationRuntimeGateFor(
      capacityProvider,
      fleetReports: fleetSnapshots.read,
    ),
  );
  final notificationDispatcher = GenerationNotificationDispatcher(
    store: notificationStore,
    messaging: firebase.adminApp.messaging(),
    webOrigin: origin,
  );
  final runBroker = WorkflowRunBroker(
    store: store,
    githubForWorkspace: githubForWorkspace,
    artifacts: artifactVerifier,
    retention: assetRetention,
    sourceAssets: sourceAssets,
    notifications: notificationDispatcher,
  );
  final sessions = await _interactiveSessions(store);
  return IiOsApi(
    auth: AuthService(
      identityProvider: FirebaseIdentityProvider(
        adminApp: firebase.adminApp,
        checkRevoked: false,
        manageCustomClaims: false,
        allowLocalDevelopment: emulated || profile == 'dev',
      ),
      systemOwners: FirestoreSystemOwnerRepository(firestore),
      bootstrapOwnerEmails: bootstrapOwnerEmails.value().split(',').toSet(),
    ),
    store: store,
    characters: CharacterStore(firestore),
    assetRetention: assetRetention,
    audit: audit,
    agentUsage: AgentUsageStore(
      projectId: agentUsageProjectId.value().trim(),
      datasetId: agentUsageDatasetId.value().trim(),
      tableId: agentUsageTableId.value().trim(),
    ),
    agentUsageKeys: agentUsageKeys,
    promptEnhancer: promptEnhancer,
    promptEnhancementKeys: promptEnhancementKeys,
    promptGuides: promptGuides,
    githubForWorkspace: githubForWorkspace,
    workflows: workflowCoordinator,
    workflowApi: WorkflowApi(
      store: store,
      tokens: tokenService,
      runs: runBroker,
      audit: audit,
      sourceAssets: sourceAssets,
      codexAuth: codexAuth,
      githubForWorkspace: githubForWorkspace,
      githubOidc: GitHubActionsOidcVerifier(
        audience: '$origin/api/v1/codex-auth-sessions',
        agentRepositories: agentRepositories,
      ),
      agentRepositories: agentRepositories,
      agentEngines: agentEngines,
    ),
    connectedDataApi: ConnectedDataApi(
      store: store,
      brokerServiceAccount: brokerServiceAccount,
      controlProjectId: runtimeProject,
      controlDatabaseId: databaseId,
      webOrigin: origin,
    ),
    notifications: notificationStore,
    organizations: organizationStore,
    fleetSnapshots: fleetSnapshots,
    fleetReportingKeys: fleetReportingKeys,
    organizationInvitations: OrganizationInvitationStore(
      firestore: firestore,
      // The same verified sender the sign-in code already uses, so invitations
      // arrive from an address recipients have seen before.
      mailer: ZeptoMailer(
        apiKey: ZEPTOMAIL_API_KEY.value(),
        fromAddress: senderAddress,
      ),
      webOrigin: origin,
      rateLimiter: OrganizationInvitationRateLimiter(
        firestore: firestore,
        codec: authCodec,
      ),
      deliveryFailureReporter: (error, stackTrace, requestId, actorUid) =>
          errors.report(
            ErrorEvent(
              source: 'api',
              errorType: 'invitation_email_delivery_failed',
              message: error is TransactionalMailRejected
                  ? error.toString()
                  : 'Transactional mail failed with ${error.runtimeType}.',
              stackTrace: stackTrace.toString(),
              requestId: requestId,
              route: 'POST /v1/organizations/invitations',
              actorUid: actorUid,
            ),
          ),
    ),
    passwordlessAuth: PasswordlessAuthService(
      adminApp: firebase.adminApp,
      firestore: firestore,
      codec: authCodec,
      sender: ZeptoMailOtpSender(
        apiKey: ZEPTOMAIL_API_KEY.value(),
        fromAddress: senderAddress,
      ),
    ),
    interactiveSessions: sessions,
    webOrigin: origin,
    agentRepositories: agentRepositories,
    agentEngines: agentEngines,
    errors: errors,
  );
}

Future<InteractiveSessionCoordinator?> _interactiveSessions(
  WorkspaceStore store,
) async {
  final relayValue = interactiveRelayUrl.value().trim();
  final imageValue = interactiveSessionImage.value().trim();
  final signingReference = interactiveGrantSigningKeySecretRef.value().trim();
  final controlReference = interactiveRelayControlSecretRef.value().trim();
  final configured = [
    relayValue,
    imageValue,
    signingReference,
    controlReference,
  ].where((item) => item.isNotEmpty).length;
  if (configured == 0) return null;
  if (configured != 4) {
    throw StateError(
      'Interactive sessions require relay URL, immutable image, signing key, '
      'and relay control secret together.',
    );
  }
  final signingValue = await _secretText(
    signingReference,
    'interactive grant signing key',
  );
  final controlValue = await _secretText(
    controlReference,
    'interactive relay control secret',
  );
  late List<int> signingKey;
  try {
    signingKey = base64Decode(signingValue);
  } on FormatException {
    throw StateError('II_OS_INTERACTIVE_GRANT_SIGNING_KEY is not base64.');
  }
  final relayUri = Uri.tryParse(relayValue);
  if (relayUri == null) {
    throw StateError('II_OS_INTERACTIVE_RELAY_URL is invalid.');
  }
  return InteractiveSessionCoordinator(
    workspaces: WorkspaceStoreInteractiveSessionAccess(store),
    sessions: FirestoreInteractiveSessionRepository(store.firestore),
    relay: HttpSessionRelayControl(
      baseUri: relayUri,
      controlSecret: controlValue,
    ),
    signer: SessionGrantSigner(signingKey),
    image: imageValue,
  );
}

Future<String> _secretText(String reference, String label) async {
  if (!RegExp(
    r'^projects/[A-Za-z0-9_-]+/secrets/[A-Za-z0-9_-]+/versions/[1-9][0-9]*$',
  ).hasMatch(reference)) {
    throw StateError('The $label Secret Manager reference is invalid.');
  }
  final client = await clientViaApplicationDefaultCredentials(
    scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
  );
  try {
    final response = await secretmanager.SecretManagerApi(
      client,
    ).projects.secrets.versions.access(reference);
    final encoded = response.payload?.data;
    if (encoded == null || encoded.isEmpty) {
      throw StateError('The $label is empty.');
    }
    return utf8.decode(base64.decode(encoded)).trim();
  } finally {
    client.close();
  }
}

Future<GitHubClient> _githubClientForWorkspace(
  WorkspaceStore store,
  Workspace workspace, {
  required bool emulated,
  required GitHubQaDeploymentCache qaDeploymentCache,
  required AgentTrustedSourceManifest agentSourceManifest,
  required AgentEngineCatalog agentEngines,
}) async {
  final resolver = WorkspaceResourceResolver(store);
  final resolved = await resolver.load(workspace.id);
  if (resolved.resourceGrantsExplicit ||
      !resolved.organizationResources.isEmpty ||
      (resolved.organizationId.isNotEmpty && resolved.connection == null)) {
    final resource = await resolver.requirePrimaryGitHub(resolved);
    final secretGcp = resolved.organizationResources.gcp(
      resource.secretGcpResourceId,
    );
    final legacySourceWorkspaceId = secretGcp?.legacySourceWorkspaceId ?? '';
    if (emulated) {
      return GitHubClient(
        appId: '',
        privateKey: '',
        qaDeploymentCache: qaDeploymentCache,
        agentTrustedSourceManifest: agentSourceManifest,
        agentEngines: agentEngines,
      );
    }
    return GitHubClient(
      appId: resource.appId,
      privateKey: await _githubPrivateKey(
        secretReference: resource.privateKeySecret,
        expectedAppId: resource.appId,
        bindingId: legacySourceWorkspaceId.isEmpty
            ? resolved.organizationId
            : legacySourceWorkspaceId,
        organizationBound: legacySourceWorkspaceId.isEmpty,
      ),
      qaDeploymentCache: qaDeploymentCache,
      agentTrustedSourceManifest: agentSourceManifest,
      agentEngines: agentEngines,
    );
  }

  // Migration shim for a standalone or not-yet-promoted V1 workspace.
  final connection = await store.resolveConnection(
    resolved,
    permission: 'workflows.upload',
  );
  if (emulated) {
    return GitHubClient(
      appId: '',
      privateKey: '',
      qaDeploymentCache: qaDeploymentCache,
      agentTrustedSourceManifest: agentSourceManifest,
      agentEngines: agentEngines,
    );
  }
  return GitHubClient(
    appId: connection.githubAppId,
    privateKey: await _githubPrivateKey(
      secretReference: connection.githubAppSecret,
      expectedAppId: connection.githubAppId,
      bindingId: connection.bindingId,
      organizationBound: connection.isOrganizationBound,
    ),
    qaDeploymentCache: qaDeploymentCache,
    agentTrustedSourceManifest: agentSourceManifest,
    agentEngines: agentEngines,
  );
}

Future<String> _githubPrivateKey({
  required String secretReference,
  required String expectedAppId,
  required String bindingId,
  required bool organizationBound,
}) async {
  if (secretReference.isEmpty) {
    throw const FormatException('The GitHub App secret reference is required.');
  }
  final client = await clientViaApplicationDefaultCredentials(
    scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
  );
  try {
    final version = secretReference.endsWith('/versions/latest')
        ? secretReference
        : '$secretReference/versions/latest';
    final response = await secretmanager.SecretManagerApi(
      client,
    ).projects.secrets.versions.access(version);
    final encoded = response.payload?.data;
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('The GitHub App secret is empty.');
    }
    final secret = GitHubAppSecret.parse(utf8.decode(base64.decode(encoded)));
    if (!secret.isBoundTo(
          bindingId: bindingId,
          organizationBound: organizationBound,
        ) ||
        (secret.appId.isNotEmpty && secret.appId != expectedAppId)) {
      throw const FormatException(
        'The GitHub App secret is bound to a different owner.',
      );
    }
    return secret.privateKey;
  } finally {
    client.close();
  }
}

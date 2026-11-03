final class DataPlaneConnection {
  const DataPlaneConnection({
    required this.workspaceId,
    this.organizationId = '',
    required this.projectId,
    required this.projectNumber,
    required this.databaseId,
    required this.region,
    required this.bucket,
    required this.dataServiceAccount,
    required this.uploadServiceAccount,
    required this.workloadIdentityProvider,
    required this.authProjectId,
    required this.webOrigin,
    this.githubAppId = '',
    this.githubAppSecret = '',
    this.gcpOnly = false,
    required this.emulated,
  });

  factory DataPlaneConnection.fromJson(
    Map<String, Object?> json, {
    bool emulated = false,
  }) {
    // Schema 2 binds a bundled legacy connection to one workspace; schema 3
    // binds the same migration shape to an organization. Schema 4 is the
    // organization-owned GCP resource and deliberately has no GitHub fields.
    final version = (json['schemaVersion'] as num?)?.toInt();
    final fields = switch (version) {
      2 => _workspaceConnectionFields,
      3 => _organizationConnectionFields,
      4 => _organizationGcpConnectionFields,
      _ => null,
    };
    if (fields == null ||
        json.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'The persisted GCP connection record has an unsupported shape.',
      );
    }
    String value(String name) =>
        json[name] is String ? (json[name]! as String).trim() : '';
    return DataPlaneConnection(
      workspaceId: version == 2 ? value('workspaceId') : '',
      organizationId: version == 3 || version == 4
          ? value('organizationId')
          : '',
      projectId: value('projectId'),
      projectNumber: value('projectNumber'),
      databaseId: value('databaseId'),
      region: value('region'),
      bucket: value('bucket'),
      dataServiceAccount: value('dataServiceAccount'),
      uploadServiceAccount: value('uploadServiceAccount'),
      workloadIdentityProvider: value('workloadIdentityProvider'),
      authProjectId: value('authProjectId'),
      webOrigin: value('webOrigin'),
      githubAppId: value('githubAppId'),
      githubAppSecret: value('githubAppSecret'),
      gcpOnly: version == 4,
      emulated: emulated,
    );
  }

  final String workspaceId;

  /// The tenant this persisted connection belongs to at organization scope.
  ///
  /// Exactly one of this and [workspaceId] is set. Which one decides what the
  /// bucket label and the GitHub App secret payload have to agree with, so a
  /// record cannot be moved between tiers by editing its version alone.
  final String organizationId;
  final String projectId;
  final String projectNumber;
  final String databaseId;
  final String region;
  final String bucket;
  final String dataServiceAccount;
  final String uploadServiceAccount;
  final String workloadIdentityProvider;
  final String authProjectId;
  final String webOrigin;
  final String githubAppId;
  final String githubAppSecret;
  final bool gcpOnly;
  final bool emulated;

  bool get isOrganizationBound => organizationId.isNotEmpty;

  /// The identifier every bound resource must agree with.
  String get bindingId => isOrganizationBound ? organizationId : workspaceId;

  /// The bucket label key that carries [bindingId].
  String get bindingLabel =>
      isOrganizationBound ? 'ii_os_organization_id' : 'ii_os_workspace_id';

  Map<String, Object?> toJson() => isOrganizationBound
      ? {
          'schemaVersion': gcpOnly ? 4 : 3,
          'organizationId': organizationId,
          ..._sharedJson,
        }
      : {'schemaVersion': 2, 'workspaceId': workspaceId, ..._sharedJson};

  Map<String, Object?> get _sharedJson => {
    'projectId': projectId,
    'projectNumber': projectNumber,
    'databaseId': databaseId,
    'region': region,
    'bucket': bucket,
    'dataServiceAccount': dataServiceAccount,
    'uploadServiceAccount': uploadServiceAccount,
    'workloadIdentityProvider': workloadIdentityProvider,
    'authProjectId': authProjectId,
    'webOrigin': webOrigin,
    if (!gcpOnly) 'githubAppId': githubAppId,
    if (!gcpOnly) 'githubAppSecret': githubAppSecret,
  };

  List<ConnectionCheck> configurationChecks() {
    final checks = <ConnectionCheck>[
      _configured(
        isOrganizationBound ? 'organization_binding' : 'workspace_binding',
        isOrganizationBound
            ? 'ii-os organization binding'
            : 'ii-os workspace binding',
        _workspaceId.hasMatch(bindingId),
      ),
      _configured('project', 'GCP project', _projectId.hasMatch(projectId)),
      _configured(
        'project_number',
        'Project number',
        emulated || _projectNumber.hasMatch(projectNumber),
      ),
      _configured(
        'firestore_database',
        'Firestore database',
        _databaseId.hasMatch(databaseId),
      ),
      _configured('region', 'GCP region', _region.hasMatch(region)),
      _configured(
        'bucket',
        'Media bucket',
        emulated || _bucket.hasMatch(bucket),
      ),
      _configured(
        'data_identity',
        'Data-plane identity',
        emulated || _serviceAccount.hasMatch(dataServiceAccount),
      ),
      _configured(
        'upload_identity',
        'Workflow upload identity',
        emulated || _serviceAccount.hasMatch(uploadServiceAccount),
      ),
      _configured(
        'github_wif',
        'GitHub Workload Identity provider',
        emulated || _provider.hasMatch(workloadIdentityProvider),
      ),
      _configured(
        'auth_boundary',
        'Platform Auth boundary',
        _projectId.hasMatch(authProjectId),
      ),
      _configured(
        'asset_project_boundary',
        'Workspace asset project boundary',
        emulated || projectId != authProjectId,
      ),
      _configured(
        'web_origin',
        'ii-os web origin',
        _validWebOrigin(webOrigin, emulated: emulated),
      ),
      if (!gcpOnly) ...[
        _configured(
          'github_app_id',
          'Customer GitHub App ID',
          emulated || RegExp(r'^[0-9]+$').hasMatch(githubAppId),
        ),
        _configured(
          'github_app_secret',
          'Customer GitHub App secret reference',
          emulated ||
              (_secret.hasMatch(githubAppSecret) &&
                  _secretBelongsToProject(
                    githubAppSecret,
                    projectId,
                    projectNumber,
                  )),
        ),
      ],
    ];
    return checks;
  }

  ConnectionCheck _configured(String id, String label, bool valid) =>
      ConnectionCheck(
        id: id,
        label: label,
        status: valid ? 'passed' : 'action_required',
        detail: valid ? 'Configured' : 'Missing or invalid',
      );
}

final class ConnectionCheck {
  const ConnectionCheck({
    required this.id,
    required this.label,
    required this.status,
    required this.detail,
  });

  final String id;
  final String label;
  final String status;
  final String detail;

  bool get passed => status == 'passed';

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'status': status,
    'detail': detail,
  };
}

final _workspaceId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _projectId = RegExp(r'^[a-z][a-z0-9-]{4,29}$');
final _projectNumber = RegExp(r'^[1-9][0-9]{5,19}$');
final _databaseId = RegExp(r'^(\(default\)|[a-z][a-z0-9-]{2,62})$');
final _region = RegExp(r'^[a-z][a-z0-9-]{1,31}$');
final _bucket = RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$');
final _serviceAccount = RegExp(
  r'^[a-z0-9][a-z0-9-]{2,28}@[a-z][a-z0-9-]{4,28}\.iam\.gserviceaccount\.com$',
);
final _provider = RegExp(
  r'^projects/[1-9][0-9]{5,19}/locations/global/workloadIdentityPools/[a-z0-9-]{4,32}/providers/[a-z0-9-]{4,32}$',
);
final _secret = RegExp(
  r'^projects/([a-z][a-z0-9-]{4,29}|[1-9][0-9]{5,19})/secrets/[a-zA-Z0-9_-]{1,255}$',
);

const _organizationConnectionFields = {
  'schemaVersion',
  'organizationId',
  'projectId',
  'projectNumber',
  'databaseId',
  'region',
  'bucket',
  'dataServiceAccount',
  'uploadServiceAccount',
  'workloadIdentityProvider',
  'authProjectId',
  'webOrigin',
  'githubAppId',
  'githubAppSecret',
};

const _organizationGcpConnectionFields = {
  'schemaVersion',
  'organizationId',
  'projectId',
  'projectNumber',
  'databaseId',
  'region',
  'bucket',
  'dataServiceAccount',
  'uploadServiceAccount',
  'workloadIdentityProvider',
  'authProjectId',
  'webOrigin',
};

const _workspaceConnectionFields = {
  'schemaVersion',
  'workspaceId',
  'projectId',
  'projectNumber',
  'databaseId',
  'region',
  'bucket',
  'dataServiceAccount',
  'uploadServiceAccount',
  'workloadIdentityProvider',
  'authProjectId',
  'webOrigin',
  'githubAppId',
  'githubAppSecret',
};

bool _secretBelongsToProject(
  String secret,
  String projectId,
  String projectNumber,
) {
  final parts = secret.split('/');
  return parts.length == 4 &&
      (parts[1] == projectId || parts[1] == projectNumber);
}

bool _validWebOrigin(String value, {required bool emulated}) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) return false;
  final local = uri.host == '127.0.0.1' || uri.host == 'localhost';
  return (uri.scheme == 'https' ||
          (emulated && local && uri.scheme == 'http')) &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

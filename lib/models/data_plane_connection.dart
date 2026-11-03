final class DataPlaneConnectionModel {
  const DataPlaneConnectionModel({
    this.workspaceId = '',
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
  });

  factory DataPlaneConnectionModel.empty() => DataPlaneConnectionModel(
    workspaceId: '',
    organizationId: '',
    projectId: '',
    projectNumber: '',
    databaseId: '',
    region: '',
    bucket: '',
    dataServiceAccount: '',
    uploadServiceAccount: '',
    workloadIdentityProvider: '',
    authProjectId: '',
    webOrigin: '',
    githubAppId: '',
    githubAppSecret: '',
    gcpOnly: false,
  );

  factory DataPlaneConnectionModel.fromJson(Map<String, Object?> json) {
    final version = (json['schemaVersion'] as num?)?.toInt();
    return DataPlaneConnectionModel(
      workspaceId: version == 3 || version == 4
          ? ''
          : json['workspaceId'] as String? ?? '',
      organizationId: version == 3 || version == 4
          ? json['organizationId'] as String? ?? ''
          : '',
      projectId: json['projectId'] as String? ?? '',
      projectNumber: json['projectNumber'] as String? ?? '',
      databaseId: json['databaseId'] as String? ?? '',
      region: json['region'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      dataServiceAccount: json['dataServiceAccount'] as String? ?? '',
      uploadServiceAccount: json['uploadServiceAccount'] as String? ?? '',
      workloadIdentityProvider:
          json['workloadIdentityProvider'] as String? ?? '',
      authProjectId: json['authProjectId'] as String? ?? '',
      webOrigin: json['webOrigin'] as String? ?? '',
      githubAppId: json['githubAppId'] as String? ?? '',
      githubAppSecret: json['githubAppSecret'] as String? ?? '',
      gcpOnly: version == 4,
    );
  }

  final String workspaceId;

  /// The tenant this persisted connection belongs to at organization scope.
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

  bool get isOrganizationBound => organizationId.isNotEmpty;

  String get bindingId => isOrganizationBound ? organizationId : workspaceId;

  bool isBoundTo({
    required String workspaceId,
    required String organizationId,
  }) {
    return isOrganizationBound
        ? this.organizationId == organizationId && organizationId.isNotEmpty
        : this.workspaceId == workspaceId && workspaceId.isNotEmpty;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': isOrganizationBound ? (gcpOnly ? 4 : 3) : 2,
    if (isOrganizationBound)
      'organizationId': organizationId
    else
      'workspaceId': workspaceId,
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

  Map<String, Object?> validationBody() => toJson();

  bool matches(DataPlaneConnectionModel other) =>
      workspaceId == other.workspaceId &&
      organizationId == other.organizationId &&
      projectId == other.projectId &&
      projectNumber == other.projectNumber &&
      databaseId == other.databaseId &&
      region == other.region &&
      bucket == other.bucket &&
      dataServiceAccount == other.dataServiceAccount &&
      uploadServiceAccount == other.uploadServiceAccount &&
      workloadIdentityProvider == other.workloadIdentityProvider &&
      authProjectId == other.authProjectId &&
      webOrigin == other.webOrigin &&
      githubAppId == other.githubAppId &&
      githubAppSecret == other.githubAppSecret &&
      gcpOnly == other.gcpOnly;

  DataPlaneConnectionModel copyWith({
    String? workspaceId,
    String? organizationId,
    String? projectId,
    String? projectNumber,
    String? databaseId,
    String? region,
    String? bucket,
    String? dataServiceAccount,
    String? uploadServiceAccount,
    String? workloadIdentityProvider,
    String? authProjectId,
    String? webOrigin,
    String? githubAppId,
    String? githubAppSecret,
    bool? gcpOnly,
  }) => DataPlaneConnectionModel(
    workspaceId: workspaceId ?? this.workspaceId,
    organizationId: organizationId ?? this.organizationId,
    projectId: projectId ?? this.projectId,
    projectNumber: projectNumber ?? this.projectNumber,
    databaseId: databaseId ?? this.databaseId,
    region: region ?? this.region,
    bucket: bucket ?? this.bucket,
    dataServiceAccount: dataServiceAccount ?? this.dataServiceAccount,
    uploadServiceAccount: uploadServiceAccount ?? this.uploadServiceAccount,
    workloadIdentityProvider:
        workloadIdentityProvider ?? this.workloadIdentityProvider,
    authProjectId: authProjectId ?? this.authProjectId,
    webOrigin: webOrigin ?? this.webOrigin,
    githubAppId: githubAppId ?? this.githubAppId,
    githubAppSecret: githubAppSecret ?? this.githubAppSecret,
    gcpOnly: gcpOnly ?? this.gcpOnly,
  );
}

final class DataPlaneValidationModel {
  const DataPlaneValidationModel({
    required this.status,
    required this.checks,
    required this.validatedAt,
  });

  factory DataPlaneValidationModel.fromJson(Map<String, Object?> json) =>
      DataPlaneValidationModel(
        status: json['status'] as String? ?? 'action_required',
        checks: (json['checks'] as List<Object?>? ?? const [])
            .map((item) => DataPlaneCheckModel.fromJson(_asJsonMap(item)))
            .toList(),
        validatedAt: DateTime.tryParse(json['validatedAt'] as String? ?? ''),
      );

  final String status;
  final List<DataPlaneCheckModel> checks;
  final DateTime? validatedAt;

  bool get ready => status == 'ready' && checks.every((check) => check.passed);

  Map<String, Object?> toJson() => {
    'status': status,
    'checks': checks.map((check) => check.toJson()).toList(),
    'validatedAt': validatedAt?.toUtc().toIso8601String(),
  };
}

final class DataPlaneCheckModel {
  const DataPlaneCheckModel({
    required this.id,
    required this.label,
    required this.status,
    required this.detail,
  });

  factory DataPlaneCheckModel.fromJson(Map<String, Object?> json) =>
      DataPlaneCheckModel(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        status: json['status'] as String? ?? 'action_required',
        detail: json['detail'] as String? ?? '',
      );

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

Map<String, Object?> _asJsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return <String, Object?>{};
}

import 'models.dart';

/// The bounded organization directory returned to a people administrator.
final class OrganizationPeopleModel {
  const OrganizationPeopleModel({
    required this.people,
    required this.workspaces,
    required this.invitations,
    this.workspaceRoles = const [],
  });

  factory OrganizationPeopleModel.fromJson(JsonMap json) =>
      OrganizationPeopleModel(
        people: _maps(
          json['members'],
        ).map(OrganizationPersonModel.fromJson).toList(growable: false),
        workspaces: _maps(
          json['workspaces'],
        ).map(OrganizationWorkspaceModel.fromJson).toList(growable: false),
        invitations: _maps(
          json['invitations'],
        ).map(OrganizationInvitationModel.fromJson).toList(growable: false),
        workspaceRoles: _maps(
          json['workspaceRoles'],
        ).map(PermissionRoleModel.fromJson).toList(growable: false),
      );

  final List<OrganizationPersonModel> people;
  final List<OrganizationWorkspaceModel> workspaces;
  final List<OrganizationInvitationModel> invitations;
  final List<PermissionRoleModel> workspaceRoles;

  OrganizationWorkspaceModel? workspace(String id) =>
      workspaces.where((item) => item.id == id).firstOrNull;
}

final class OrganizationPersonModel {
  const OrganizationPersonModel({
    required this.uid,
    required this.email,
    required this.role,
    required this.roleLabel,
    this.featureClaims = const {},
    this.effectiveCapabilities = const {},
  });

  factory OrganizationPersonModel.fromJson(JsonMap json) =>
      OrganizationPersonModel(
        uid: json['uid']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'member',
        roleLabel: json['roleLabel']?.toString() ?? 'Organization Member',
        featureClaims: _strings(json['featureClaims']).toSet(),
        effectiveCapabilities: _strings(json['effectiveCapabilities']).toSet(),
      );

  final String uid;
  final String email;
  final String role;
  final String roleLabel;
  final Set<String> featureClaims;
  final Set<String> effectiveCapabilities;
}

final class OrganizationWorkspaceModel {
  const OrganizationWorkspaceModel({
    required this.id,
    required this.name,
    required this.environment,
  });

  factory OrganizationWorkspaceModel.fromJson(JsonMap json) =>
      OrganizationWorkspaceModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Untitled workspace',
        environment: json['environment']?.toString() ?? 'dev',
      );

  final String id;
  final String name;
  final String environment;
}

final class OrganizationInvitationModel {
  const OrganizationInvitationModel({
    required this.id,
    required this.email,
    required this.role,
    required this.roleLabel,
    required this.workspaceIds,
    required this.deliveryStatus,
    required this.expiresAt,
  });

  factory OrganizationInvitationModel.fromJson(JsonMap json) =>
      OrganizationInvitationModel(
        id: json['id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'member',
        roleLabel: json['roleLabel']?.toString() ?? 'Organization Member',
        workspaceIds: _strings(json['workspaceGrants']),
        deliveryStatus: json['deliveryStatus']?.toString() ?? 'sending',
        expiresAt: DateTime.tryParse(
          json['expiresAt']?.toString() ?? '',
        )?.toUtc(),
      );

  final String id;
  final String email;
  final String role;
  final String roleLabel;
  final List<String> workspaceIds;
  final String deliveryStatus;
  final DateTime? expiresAt;
}

final class WorkspaceAssignmentModel {
  const WorkspaceAssignmentModel({
    required this.workspaceId,
    required this.role,
    required this.roleLabel,
    required this.suspended,
    this.featureClaims = const {},
    this.effectiveCapabilities = const {},
  });

  factory WorkspaceAssignmentModel.fromJson(JsonMap json) =>
      WorkspaceAssignmentModel(
        workspaceId: json['workspaceId']?.toString() ?? '',
        role: json['role']?.toString() ?? 'view_only',
        roleLabel: json['roleLabel']?.toString() ?? 'Workspace Viewer',
        suspended: json['suspended'] == true,
        featureClaims: _strings(json['featureClaims']).toSet(),
        effectiveCapabilities: _strings(json['effectiveCapabilities']).toSet(),
      );

  final String workspaceId;
  final String role;
  final String roleLabel;
  final bool suspended;
  final Set<String> featureClaims;
  final Set<String> effectiveCapabilities;

  WorkspaceAssignmentModel withSuspended(bool value) =>
      WorkspaceAssignmentModel(
        workspaceId: workspaceId,
        role: role,
        roleLabel: roleLabel,
        suspended: value,
        featureClaims: featureClaims,
        effectiveCapabilities: value ? const {} : effectiveCapabilities,
      );
}

/// One editable workspace role and the capabilities inside its ceiling.
final class PermissionRoleModel {
  const PermissionRoleModel({
    required this.id,
    required this.label,
    required this.capabilities,
  });

  factory PermissionRoleModel.fromJson(JsonMap json) => PermissionRoleModel(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? 'Workspace role',
    capabilities: _maps(
      json['capabilities'],
    ).map(PermissionCapabilityModel.fromJson).toList(growable: false),
  );

  final String id;
  final String label;
  final List<PermissionCapabilityModel> capabilities;
}

/// Human-facing permission copy paired with its backend authorization id.
final class PermissionCapabilityModel {
  const PermissionCapabilityModel({required this.id, required this.label});

  factory PermissionCapabilityModel.fromJson(JsonMap json) =>
      PermissionCapabilityModel(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Workspace permission',
      );

  final String id;
  final String label;
}

final class WorkspaceAccessChangeModel {
  const WorkspaceAccessChangeModel({
    required this.workspaceId,
    required this.suspended,
    required this.granted,
    required this.notificationDelivered,
  });

  factory WorkspaceAccessChangeModel.fromJson(JsonMap json) =>
      WorkspaceAccessChangeModel(
        workspaceId: json['workspaceId']?.toString() ?? '',
        suspended: json['suspended'] == true,
        granted: json['granted'] == true,
        notificationDelivered: json['notificationDelivered'] as bool?,
      );

  final String workspaceId;
  final bool suspended;
  final bool granted;
  final bool? notificationDelivered;
}

List<JsonMap> _maps(Object? value) => value is List<Object?>
    ? value.map(asJsonMap).toList(growable: false)
    : const <JsonMap>[];

List<String> _strings(Object? value) => value is List<Object?>
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

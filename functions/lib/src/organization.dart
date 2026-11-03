import 'domain.dart';
import 'organization_resources.dart';

/// What a person may do at the tenant tier.
///
/// An organization is the tenant: it owns the GitHub Apps, GCP projects, and
/// runner pools, and a workspace is a project inside one. The roles are
/// deliberately fewer than [WorkspaceRole] because the tier answers fewer
/// questions -- who belongs to us, who may administer shared resources, and who
/// may hand out projects.
enum OrganizationRole {
  owner('owner', 'Organization Owner'),
  admin('admin', 'Organization Admin'),
  member('member', 'Organization Member');

  const OrganizationRole(this.value, this.label);

  final String value;
  final String label;

  static OrganizationRole parse(Object? value) {
    return OrganizationRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => throw const FormatException('Unknown organization role'),
    );
  }
}

/// Capabilities that exist at the organization tier.
///
/// Namespaced so an organization grant can never be read as a workspace grant,
/// and so an audit entry says which tier it was made at without needing the
/// surrounding context.
enum OrganizationCapability {
  read('org.read'),
  manage('org.manage'),
  membersManage('org.members.manage'),
  credentialsManage('org.credentials.manage'),
  integrationsManage('org.integrations.manage'),
  runnersManage('org.runners.manage'),
  workspacesCreate('org.workspaces.create'),
  workspacesAccessManage('org.workspaces.access.manage'),
  auditRead('org.audit.read');

  const OrganizationCapability(this.value);

  final String value;

  static OrganizationCapability? tryParse(String value) {
    for (final capability in OrganizationCapability.values) {
      if (capability.value == value) return capability;
    }
    return null;
  }
}

/// The ceiling each organization role may be granted up to.
///
/// Organization Admin can administer the tenant resource pool. Workspace Admin
/// cannot: the scope in the role name is the boundary, not presentation copy.
const Map<OrganizationRole, Set<OrganizationCapability>>
organizationRoleCapabilityCeilings = {
  OrganizationRole.owner: {...OrganizationCapability.values},
  OrganizationRole.admin: {
    OrganizationCapability.read,
    OrganizationCapability.manage,
    OrganizationCapability.membersManage,
    OrganizationCapability.credentialsManage,
    OrganizationCapability.integrationsManage,
    OrganizationCapability.runnersManage,
    OrganizationCapability.workspacesCreate,
    OrganizationCapability.workspacesAccessManage,
    OrganizationCapability.auditRead,
  },
  OrganizationRole.member: {OrganizationCapability.read},
};

/// What a role carries without anyone having granted it.
///
/// [OrganizationCapability.read] is the obvious one: belonging to the directory
/// at all is what it says, and withholding it would produce a member who cannot
/// see the organization they are a member of.
///
/// Admin carries the organization management bundle. This is deliberately
/// separate from a Workspace Admin, whose workspace capability ceiling cannot
/// add or widen any resource here. `credentialsManage` stays implied only as a
/// compatibility alias while singular connection routes are retired.
///
/// An Owner holds its whole ceiling outright and does not consult this.
const Map<OrganizationRole, Set<OrganizationCapability>>
organizationRoleImpliedCapabilities = {
  OrganizationRole.admin: {
    OrganizationCapability.read,
    OrganizationCapability.manage,
    OrganizationCapability.membersManage,
    OrganizationCapability.credentialsManage,
    OrganizationCapability.integrationsManage,
    OrganizationCapability.runnersManage,
    OrganizationCapability.workspacesCreate,
    OrganizationCapability.workspacesAccessManage,
    OrganizationCapability.auditRead,
  },
  OrganizationRole.member: {OrganizationCapability.read},
};

/// One person's standing in one organization.
final class OrganizationMembership {
  const OrganizationMembership({
    required this.organizationId,
    required this.uid,
    required this.email,
    required this.role,
    required this.featureClaims,
  });

  factory OrganizationMembership.fromData(Map<String, Object?> data) {
    final rawFeatures = data['featureClaims'];
    return OrganizationMembership(
      organizationId: data['organizationId'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: OrganizationRole.parse(data['role']),
      featureClaims: rawFeatures is List<Object?>
          ? rawFeatures.whereType<String>().toSet()
          : <String>{},
    );
  }

  final String organizationId;
  final String uid;
  final String email;
  final OrganizationRole role;
  final Set<String> featureClaims;

  /// What this membership actually carries.
  ///
  /// An Owner holds its whole ceiling outright, exactly as a workspace Owner
  /// does. Admin and Member add their implied role bundle to any explicit
  /// claims, always inside the role ceiling.
  Set<OrganizationCapability> get effectiveCapabilities {
    final ceiling =
        organizationRoleCapabilityCeilings[role] ??
        const <OrganizationCapability>{};
    if (role == OrganizationRole.owner) return {...ceiling};
    final effective = featureClaims
        .map(OrganizationCapability.tryParse)
        .whereType<OrganizationCapability>()
        .where(ceiling.contains)
        .toSet();
    // Everything the role carries on its own, still bounded by the ceiling so
    // the two tables can never disagree about what a role may hold.
    effective.addAll(
      (organizationRoleImpliedCapabilities[role] ??
              const <OrganizationCapability>{})
          .where(ceiling.contains),
    );
    return effective;
  }

  bool allows(OrganizationCapability capability) =>
      effectiveCapabilities.contains(capability);

  Map<String, Object?> toJson() => {
    'organizationId': organizationId,
    'uid': uid,
    'email': email,
    'role': role.value,
    'roleLabel': role.label,
    'featureClaims': featureClaims.toList()..sort(),
    'effectiveCapabilities':
        effectiveCapabilities.map((item) => item.value).toList()..sort(),
  };
}

/// The tenant record.
///
/// It owns the nonsecret identifiers that bind the tenant's GitHub and GCP
/// connection, while secret values remain in the tenant's Secret Manager.
final class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.createdBy,
    this.githubInstallationId,
    this.repositories = const <String>{},
    this.resourceCatalog = const OrganizationResourceCatalog.empty(),
  });

  factory Organization.fromData(
    String id,
    Map<String, Object?> data, {
    bool emulated = false,
  }) {
    final rawRepositories = data['repositories'];
    return Organization(
      id: id,
      name: data['name'] as String? ?? 'Untitled organization',
      createdBy: data['createdBy'] as String? ?? '',
      githubInstallationId: (data['githubInstallationId'] as num?)?.toInt(),
      repositories: rawRepositories is List<Object?>
          ? rawRepositories.whereType<String>().toSet()
          : const <String>{},
      resourceCatalog: OrganizationResourceCatalog.fromOrganizationData(
        id,
        data,
        emulated: emulated,
      ),
    );
  }

  final String id;
  final String name;
  final String createdBy;
  final int? githubInstallationId;

  /// Every repository this tenant's GitHub App installation may be used for.
  ///
  /// Presence of the field distinguishes a declared empty set (allow nothing)
  /// from a legacy organization that has not declared its boundary yet.
  final Set<String> repositories;
  final OrganizationResourceCatalog resourceCatalog;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdBy': createdBy,
    'githubInstallationId': githubInstallationId,
    'repositories': repositories.toList()..sort(),
    ...resourceCatalog.toJson(),
  };
}

/// The claims [actor] may place on a membership carrying [targetRole].
///
/// The same bound the workspace tier already applies: a grant is limited by the
/// target role's ceiling and by what the actor personally holds, so
/// `org.members.manage` delegates the access its holder has rather than
/// unlocking the tier.
List<String> boundedOrganizationClaims({
  required OrganizationMembership actor,
  required OrganizationRole targetRole,
  required Set<String> requested,
}) {
  final ceiling =
      organizationRoleCapabilityCeilings[targetRole] ??
      const <OrganizationCapability>{};
  final grantable = ceiling.intersection(actor.effectiveCapabilities);
  return requested
      .map(OrganizationCapability.tryParse)
      .whereType<OrganizationCapability>()
      .where(grantable.contains)
      .map((item) => item.value)
      .toList()
    ..sort();
}

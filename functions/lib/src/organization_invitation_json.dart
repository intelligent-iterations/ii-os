import 'organization.dart';

Map<String, Object?> organizationInvitationAdminJson(
  String id,
  Map<String, Object?> data, {
  required String? createdAt,
  required String? expiresAt,
}) {
  final role = OrganizationRole.parse(data['role']);
  return {
    'id': id,
    'email': data['email'] as String? ?? '',
    'role': role.value,
    'roleLabel': role.label,
    'workspaceGrants':
        (data['workspaceGrants'] as List<Object?>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[],
    'deliveryStatus': switch (data['delivered']) {
      true => 'delivered',
      false => 'failed',
      _ => 'sending',
    },
    'deliveryError': data['deliveryError'],
    'createdAt': createdAt,
    'expiresAt': expiresAt,
  };
}

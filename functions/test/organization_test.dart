import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/organization.dart';
import 'package:test/test.dart';

void main() {
  group('organization roles', () {
    test('an Owner holds the whole tier outright', () {
      const owner = OrganizationMembership(
        organizationId: 'org-1',
        uid: 'owner-1',
        email: 'owner@example.com',
        role: OrganizationRole.owner,
        featureClaims: {},
      );

      for (final capability in OrganizationCapability.values) {
        expect(owner.allows(capability), isTrue, reason: capability.value);
      }
    });

    test('a Member sees the organization and can do nothing else', () {
      const member = OrganizationMembership(
        organizationId: 'org-1',
        uid: 'member-1',
        email: 'member@example.com',
        role: OrganizationRole.member,
        // Requested, but outside the Member ceiling.
        featureClaims: {'org.members.manage', 'org.credentials.manage'},
      );

      expect(member.allows(OrganizationCapability.read), isTrue);
      expect(member.allows(OrganizationCapability.membersManage), isFalse);
      expect(member.allows(OrganizationCapability.credentialsManage), isFalse);
    });

    test('an Organization Admin manages the organization resource pool', () {
      const plain = OrganizationMembership(
        organizationId: 'org-1',
        uid: 'admin-1',
        email: 'admin@example.com',
        role: OrganizationRole.admin,
        featureClaims: {'org.members.manage'},
      );
      expect(plain.allows(OrganizationCapability.credentialsManage), isTrue);
      expect(plain.allows(OrganizationCapability.integrationsManage), isTrue);
      expect(plain.allows(OrganizationCapability.runnersManage), isTrue);
      expect(plain.allows(OrganizationCapability.membersManage), isTrue);
      expect(plain.role.label, 'Organization Admin');
    });

    test('every role can see the organization it belongs to', () {
      for (final role in OrganizationRole.values) {
        final membership = OrganizationMembership(
          organizationId: 'org-1',
          uid: 'user',
          email: 'user@example.com',
          role: role,
          featureClaims: const {},
        );
        expect(
          membership.allows(OrganizationCapability.read),
          isTrue,
          reason: role.value,
        );
      }
    });
  });

  group('capabilities a role carries on its own', () {
    OrganizationMembership member(OrganizationRole role) =>
        OrganizationMembership(
          organizationId: 'org-1',
          uid: 'user',
          email: 'user@example.com',
          role: role,
          featureClaims: const {},
        );

    test('an Admin can read the audit surface without being granted it', () {
      // An administrator who cannot see what the organization's own machines
      // are doing is an administrator of nothing observable.
      expect(
        member(OrganizationRole.admin).allows(OrganizationCapability.auditRead),
        isTrue,
      );
    });

    test('a Member cannot, and no grant can lift it', () {
      final plain = member(OrganizationRole.member);
      expect(plain.allows(OrganizationCapability.auditRead), isFalse);

      // Even granted outright it stays out, because the Member ceiling bounds
      // the implied table and the explicit one alike.
      final granted = OrganizationMembership(
        organizationId: 'org-1',
        uid: 'user',
        email: 'user@example.com',
        role: OrganizationRole.member,
        featureClaims: const {'org.audit.read'},
      );
      expect(granted.allows(OrganizationCapability.auditRead), isFalse);
    });

    test('an Organization Admin carries the tenant management bundle', () {
      expect(
        member(
          OrganizationRole.admin,
        ).allows(OrganizationCapability.credentialsManage),
        isTrue,
      );
      expect(
        member(OrganizationRole.admin).allows(OrganizationCapability.manage),
        isTrue,
      );
      expect(
        member(
          OrganizationRole.admin,
        ).allows(OrganizationCapability.integrationsManage),
        isTrue,
      );
    });

    test('an Owner still holds its whole ceiling', () {
      final owner = member(OrganizationRole.owner);
      for (final capability in OrganizationCapability.values) {
        expect(owner.allows(capability), isTrue, reason: capability.value);
      }
    });
  });

  group('bounded organization claims', () {
    const delegatedAdmin = OrganizationMembership(
      organizationId: 'org-1',
      uid: 'admin-1',
      email: 'admin@example.com',
      role: OrganizationRole.admin,
      featureClaims: {'org.members.manage'},
    );

    test('an Organization Admin can grant its management bundle', () {
      final claims = boundedOrganizationClaims(
        actor: delegatedAdmin,
        targetRole: OrganizationRole.admin,
        requested: OrganizationCapability.values
            .map((item) => item.value)
            .toSet(),
      );

      expect(
        claims,
        OrganizationCapability.values.map((item) => item.value).toList()
          ..sort(),
      );
    });

    test('the target role ceiling still bounds an Owner', () {
      const owner = OrganizationMembership(
        organizationId: 'org-1',
        uid: 'owner-1',
        email: 'owner@example.com',
        role: OrganizationRole.owner,
        featureClaims: {},
      );

      final claims = boundedOrganizationClaims(
        actor: owner,
        targetRole: OrganizationRole.member,
        requested: {'org.credentials.manage', 'org.read'},
      );

      expect(claims, ['org.read']);
    });

    test('unknown claim strings are dropped, not granted', () {
      final claims = boundedOrganizationClaims(
        actor: delegatedAdmin,
        targetRole: OrganizationRole.admin,
        requested: {'org.read', 'org.destroy', ''},
      );

      expect(claims, ['org.read']);
    });
  });

  test('a workspace records the tenant it belongs to', () {
    final linked = Workspace.fromData('workspace-1', {
      'name': 'Admin workspace',
      'organizationId': 'org-1',
    });
    final unlinked = Workspace.fromData('workspace-2', {
      'name': 'Not yet backfilled',
    });

    expect(linked.organizationId, 'org-1');
    expect(linked.toJson()['organizationId'], 'org-1');
    // Empty is a real state: the tier exists before anything depends on it.
    expect(unlinked.organizationId, isEmpty);
  });
}

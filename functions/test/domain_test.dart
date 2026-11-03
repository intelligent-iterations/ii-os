import 'package:ii_os_functions/src/domain.dart';
import 'package:test/test.dart';

void main() {
  group('workspace RBAC', () {
    test(
      'permission catalog exposes every role and capability with UI copy',
      () {
        final catalog = workspacePermissionRoleCatalog();
        expect(
          catalog.map((entry) => entry['id']).toSet(),
          WorkspaceRole.values.map((role) => role.value).toSet(),
        );
        final capabilities = catalog
            .expand(
              (role) => (role['capabilities']! as List<Object?>)
                  .whereType<Map<String, Object?>>(),
            )
            .toList(growable: false);
        expect(
          capabilities.map((entry) => entry['id']).toSet(),
          Capability.values.map((capability) => capability.value).toSet(),
        );
        expect(
          capabilities.every(
            (entry) => (entry['label'] as String?)?.trim().isNotEmpty == true,
          ),
          isTrue,
        );
      },
    );

    test('triggering jobs implies reading them for every role', () {
      // The source-asset routes floor the family at jobsRead and escalate to
      // jobsTrigger for uploads. That is only non-regressive while no role can
      // hold jobsTrigger without jobsRead.
      for (final role in WorkspaceRole.values) {
        final ceiling = roleCapabilityCeilings[role] ?? const <Capability>{};
        if (!ceiling.contains(Capability.jobsTrigger)) continue;
        expect(
          ceiling.contains(Capability.jobsRead),
          isTrue,
          reason: '${role.name} may trigger jobs but not read them',
        );
        final membership = Membership(
          workspaceId: 'workspace-1',
          uid: 'member-1',
          email: 'member@example.com',
          role: role,
          featureClaims: const {'jobs.trigger'},
        );
        expect(
          membership.allows(Capability.jobsRead),
          isTrue,
          reason: '${role.name} lost read access when only granted trigger',
        );
      }
    });

    test('writing tickets implies reading installed permission profiles', () {
      for (final role in WorkspaceRole.values) {
        final ceiling = roleCapabilityCeilings[role] ?? const <Capability>{};
        if (!ceiling.contains(Capability.ticketsWrite)) continue;
        final membership = Membership(
          workspaceId: 'workspace-1',
          uid: 'ticket-author-1',
          email: 'ticket-author@example.com',
          role: role,
          featureClaims: const {'tickets.write'},
        );

        expect(
          membership.allows(Capability.agentPermissionsRead),
          isTrue,
          reason:
              '${role.name} may create and queue tickets but cannot read '
              'their installed permission profile',
        );
        if (role != WorkspaceRole.owner) {
          expect(
            membership.allows(Capability.agentPermissionsManage),
            isFalse,
            reason: '${role.name} gained permission management access',
          );
        }
      }
    });

    test('AI cannot mutate tickets even when the claim is requested', () {
      const membership = Membership(
        workspaceId: 'workspace-1',
        uid: 'ai-1',
        email: 'ai@example.com',
        role: WorkspaceRole.ai,
        featureClaims: {
          'tickets.write',
          'agent.permissions.read',
          'agent.permissions.manage',
          'project.fields.manage',
          'characters.write',
          'jobs.trigger',
          'agent.usage.write',
        },
      );

      expect(membership.allows(Capability.jobsTrigger), isTrue);
      expect(membership.allows(Capability.jobsRead), isTrue);
      expect(membership.allows(Capability.charactersWrite), isTrue);
      expect(membership.allows(Capability.ticketsWrite), isFalse);
      expect(membership.allows(Capability.agentPermissionsRead), isTrue);
      expect(membership.allows(Capability.agentPermissionsManage), isFalse);
      expect(membership.allows(Capability.projectFieldsManage), isFalse);
      expect(membership.allows(Capability.agentUsageWrite), isTrue);
    });

    test('job generation includes access to generated-media history', () {
      const membership = Membership(
        workspaceId: 'workspace-1',
        uid: 'editor-1',
        email: 'editor@example.com',
        role: WorkspaceRole.editor,
        featureClaims: {'jobs.trigger'},
      );

      expect(membership.allows(Capability.jobsTrigger), isTrue);
      expect(membership.allows(Capability.jobsRead), isTrue);
      expect(membership.allows(Capability.ticketsRead), isFalse);
    });

    test('feature claims can narrow but cannot expand a role ceiling', () {
      const membership = Membership(
        workspaceId: 'workspace-1',
        uid: 'editor-1',
        email: 'editor@example.com',
        role: WorkspaceRole.editor,
        featureClaims: {'tickets.read', 'members.manage'},
      );

      expect(membership.allows(Capability.ticketsRead), isTrue);
      expect(membership.allows(Capability.jobsTrigger), isFalse);
      expect(membership.allows(Capability.membersManage), isFalse);
      expect(membership.allows(Capability.charactersWrite), isFalse);
    });

    test('empty claims grant no capabilities to a workspace role', () {
      const membership = Membership(
        workspaceId: 'workspace-1',
        uid: 'viewer-1',
        email: 'viewer@example.com',
        role: WorkspaceRole.viewOnly,
        featureClaims: {},
      );

      expect(membership.allows(Capability.workspaceRead), isFalse);
      expect(membership.allows(Capability.ticketsWrite), isFalse);
    });

    test('workspace Owner retains the full capability ceiling', () {
      const membership = Membership(
        workspaceId: 'workspace-1',
        uid: 'owner-1',
        email: 'owner@example.com',
        role: WorkspaceRole.owner,
        featureClaims: {},
      );

      expect(membership.allows(Capability.membersManage), isTrue);
      expect(membership.allows(Capability.jobsTrigger), isTrue);
    });

    test(
      'interactive sessions are independently grantable to eligible users',
      () {
        const membership = Membership(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: WorkspaceRole.editor,
          featureClaims: {
            'interactive.sessions.read',
            'interactive.sessions.launch',
          },
        );
        expect(membership.allows(Capability.interactiveSessionsRead), isTrue);
        expect(membership.allows(Capability.interactiveSessionsLaunch), isTrue);
        expect(
          membership.allows(Capability.interactiveSessionsManage),
          isFalse,
        );
      },
    );

    test('interactive sessions cannot be expanded onto view-only users', () {
      const membership = Membership(
        workspaceId: 'workspace-1',
        uid: 'viewer-1',
        email: 'viewer@example.com',
        role: WorkspaceRole.viewOnly,
        featureClaims: {
          'interactive.sessions.read',
          'interactive.sessions.launch',
        },
      );
      expect(membership.allows(Capability.interactiveSessionsRead), isTrue);
      expect(membership.allows(Capability.interactiveSessionsLaunch), isFalse);
    });
  });

  group('grantable capabilities', () {
    const narrowedAdmin = Membership(
      workspaceId: 'workspace-1',
      uid: 'admin-1',
      email: 'admin@example.com',
      role: WorkspaceRole.admin,
      featureClaims: {'members.manage', 'workspace.read', 'characters.read'},
    );
    const owner = Membership(
      workspaceId: 'workspace-1',
      uid: 'owner-1',
      email: 'owner@example.com',
      role: WorkspaceRole.owner,
      featureClaims: {},
    );

    test('an actor cannot grant a capability it does not hold', () {
      final claims = boundedFeatureClaims(
        actor: narrowedAdmin,
        targetRole: WorkspaceRole.editor,
        requested: {
          'workspace.read',
          'characters.read',
          'characters.write',
          'jobs.trigger',
          'pull_requests.merge',
        },
      );

      expect(claims, ['characters.read', 'workspace.read']);
    });

    test('members.manage is not a route to every other capability', () {
      final claims = boundedFeatureClaims(
        actor: narrowedAdmin,
        targetRole: WorkspaceRole.admin,
        requested: Capability.values.map((item) => item.value).toSet(),
      );

      expect(claims, ['characters.read', 'members.manage', 'workspace.read']);
    });

    test('an Owner can grant the whole ceiling of the assigned role', () {
      final claims = boundedFeatureClaims(
        actor: owner,
        targetRole: WorkspaceRole.viewOnly,
        requested: Capability.values.map((item) => item.value).toSet(),
      );

      expect(
        claims,
        (roleCapabilityCeilings[WorkspaceRole.viewOnly]!
            .map((item) => item.value)
            .toList()
          ..sort()),
      );
    });

    test('the assigned role ceiling still bounds an Owner', () {
      final claims = boundedFeatureClaims(
        actor: owner,
        targetRole: WorkspaceRole.ai,
        requested: {'tickets.write', 'jobs.trigger'},
      );

      expect(claims, ['jobs.trigger']);
    });

    test('unknown claim strings are dropped, not granted', () {
      final claims = boundedFeatureClaims(
        actor: owner,
        targetRole: WorkspaceRole.editor,
        requested: {'workspace.read', 'workspace.destroy', ''},
      );

      expect(claims, ['workspace.read']);
    });
  });

  test(
    'legacy connector-shaped workspace state is treated as disconnected',
    () {
      final workspace = Workspace.fromData('workspace-1', {
        'name': 'Legacy workspace',
        'connection': {
          'schemaVersion': 1,
          'apiBaseUrl': 'https://connector.example',
        },
      });

      expect(workspace.connection, isNull);
    },
  );
}

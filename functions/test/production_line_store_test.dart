import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/production_line_store.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a complete production line bound to workspace resources', () {
    final fields = validatedProductionLineFields(
      _body(),
      _workspace,
      requireAll: true,
    );

    expect(fields['name'], 'Payments');
    expect(fields['repository'], 'acme/payments');
    expect(fields['projectId'], 'PVT_kwDO');
    expect(fields['colorToken'], 'violet');
    expect(fields['iconToken'], 'creditCard');
  });

  test('trims the name rather than storing the operator typo', () {
    final fields = validatedProductionLineFields(
      {..._body(), 'name': '  Payments  '},
      _workspace,
      requireAll: true,
    );

    expect(fields['name'], 'Payments');
  });

  test('rejects unknown fields, unbound resources, and open-ended tokens', () {
    final mutations = <Map<String, Object?> Function()>[
      // An unknown key is rejected rather than dropped, so a typo fails loudly.
      () => {..._body(), 'permissionScope': 'wide'},
      // A line may only point at resources the workspace actually installed.
      () => {..._body(), 'repository': 'acme/not-installed'},
      () => {..._body(), 'projectId': 'PVT_unknown'},
      // Identity is a closed token set, never a caller-supplied hex or glyph.
      () => {..._body(), 'colorToken': '#FF0000'},
      () => {..._body(), 'colorToken': 'green'},
      () => {..._body(), 'iconToken': 'skull'},
      // Names are bounded and required.
      () => {..._body(), 'name': ''},
      () => {..._body(), 'name': '   '},
      () => {..._body(), 'name': 'x' * 81},
      () => {..._body(), 'name': 42},
    ];

    for (final mutation in mutations) {
      expect(
        () => validatedProductionLineFields(
          mutation(),
          _workspace,
          requireAll: true,
        ),
        throwsA(isA<ApiError>()),
        reason: 'accepted ${mutation()}',
      );
    }
  });

  test('requires every field on create but allows a partial update', () {
    final partial = {'name': 'Renamed'};

    expect(
      () =>
          validatedProductionLineFields(partial, _workspace, requireAll: true),
      throwsA(isA<ApiError>()),
    );
    expect(
      validatedProductionLineFields(partial, _workspace, requireAll: false),
      {'name': 'Renamed'},
    );
  });

  test('identity tokens stay disjoint from the status palette', () {
    // green, amber, and red carry success/warning/error meaning. A line that
    // could claim one would make its own status pills unreadable.
    expect(
      productionLineColorTokens.intersection({'green', 'amber', 'red'}),
      isEmpty,
    );
  });

  test('round-trips through Firestore data without losing identity', () {
    final line = ProductionLine.fromData('line-1', {
      ..._body(),
      'workspaceId': 'workspace-1',
    });

    expect(line.id, 'line-1');
    expect(line.toJson()['iconToken'], 'creditCard');
    expect(line.toJson()['permissionRef'], 'dev');
  });

  test('an AI identity can read lines but never grant or reshape one', () {
    final ceiling = roleCapabilityCeilings[WorkspaceRole.ai]!;

    expect(ceiling, contains(Capability.linesRead));
    expect(ceiling, isNot(contains(Capability.linesManage)));
    expect(ceiling, isNot(contains(Capability.linesMembersManage)));
  });

  test('only Owner and Admin may reshape a line or its membership', () {
    for (final role in [WorkspaceRole.editor, WorkspaceRole.viewOnly]) {
      final ceiling = roleCapabilityCeilings[role]!;
      expect(ceiling, contains(Capability.linesRead), reason: '$role');
      expect(ceiling, isNot(contains(Capability.linesManage)), reason: '$role');
      expect(
        ceiling,
        isNot(contains(Capability.linesMembersManage)),
        reason: '$role',
      );
    }
    for (final role in [WorkspaceRole.owner, WorkspaceRole.admin]) {
      expect(
        roleCapabilityCeilings[role],
        containsAll([
          Capability.linesRead,
          Capability.linesManage,
          Capability.linesMembersManage,
        ]),
        reason: '$role',
      );
    }
  });
}

Map<String, Object?> _body() => {
  'name': 'Payments',
  'repository': 'acme/payments',
  'projectId': 'PVT_kwDO',
  'permissionProfileId': 'repository-maintainer',
  'permissionRef': 'dev',
  'colorToken': 'violet',
  'iconToken': 'creditCard',
};

final _workspace = Workspace(
  id: 'workspace-1',
  name: 'Acme',
  environment: 'dev',
  githubInstallationId: 1,
  repositories: const ['acme/payments', 'acme/mobile'],
  projects: [
    GitHubProjectConfig.fromJson(const {
      'id': 'PVT_kwDO',
      'owner': 'acme',
      'number': 4,
    }),
  ],
  workflows: const [],
  artifactStorage: null,
);

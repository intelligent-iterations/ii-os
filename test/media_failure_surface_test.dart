import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/services/client_error_reporter.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/storyboard_editor_components.dart';
import 'package:ii_os/widgets/unexpected_error_view.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('incomplete storyboard media renders its inline fallback', (
    tester,
  ) async {
    final reports = <JsonMap>[];
    final reporter = ClientErrorReporter(
      sender: (payload) async => reports.add(payload),
    );
    ClientErrorReporter.install(reporter);
    addTearDown(reporter.close);
    const connection = DataPlaneConnectionModel(
      workspaceId: 'workspace-1',
      projectId: 'workspace-project',
      projectNumber: '123',
      databaseId: 'workspace',
      region: 'northamerica-northeast1',
      bucket: 'workspace-media',
      dataServiceAccount: 'data@example.invalid',
      uploadServiceAccount: 'upload@example.invalid',
      workloadIdentityProvider: 'provider',
      authProjectId: 'auth-project',
      webOrigin: 'https://example.invalid',
    );
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#image-edit-qwen-2511'],
          artifactStorage: null,
          connection: connection,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {},
          capabilities: {},
        ),
      )
      ..connection = connection;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: SizedBox(
          width: 240,
          height: 160,
          child: StoryboardArtifactImage(
            controller: controller,
            workspaceId: 'workspace-1',
            jobId: 'job-1',
            artifact: const {
              'path': 'workspaces/workspace-1/runs/job-1/panel.png',
              'generation': '41',
              'content_type': 'image/png',
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(LucideIcons.imageOff), findsOneWidget);
    expect(reports.single['source'], 'storyboard.artifact.verified');
    expect(reports.single['workspaceId'], 'workspace-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unexpected build failures use the recoverable ii-os surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: buildIiOsErrorWidget(
          FlutterErrorDetails(exception: StateError('test failure')),
        ),
      ),
    );

    expect(find.text('This screen could not be displayed'), findsOneWidget);
    expect(find.text('Return home'), findsOneWidget);
    expect(find.byType(IiOsUnexpectedErrorView), findsOneWidget);
  });
}

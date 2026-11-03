import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/workshop_room.dart';
import 'package:ii_os/screens/software_workshop_screen.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('active Workshop scopes its initial load and refresh', (
    tester,
  ) async {
    final projectRequests = <Uri>[];
    final api = ApiClient(
      baseUrl: 'https://control.example/api',
      reportFailures: false,
      authTokenProvider: (_) async => 'synthetic-session',
      httpClient: MockClient((request) async {
        final route = request.url.queryParameters['route'];
        if (route == 'v1/workspaces/workspace-1/projects') {
          projectRequests.add(request.url);
          if (request.url.queryParameters['repository'] != 'acme/product') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'github_auth_failed',
                  'message':
                      'GitHub rejected the request: There is at least one '
                      'repository that does not exist or is not accessible '
                      'to the parent installation.',
                },
              }),
              422,
            );
          }
          return http.Response(
            jsonEncode({
              'project': {
                'id': 'project-1',
                'fields': {'nodes': []},
                'items': {'nodes': []},
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    final controller = AppController(api: api)
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Product',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/unavailable', 'acme/product'],
          projects: [
            ProjectConnection(
              id: 'project-1',
              number: 1,
              owner: 'acme',
              title: 'Product delivery',
            ),
          ],
          workshopRooms: [
            WorkshopRoomModel(
              id: 'main',
              name: 'Main room',
              color: 'violet',
              repositories: ['acme/unavailable', 'acme/product'],
              projectId: 'project-1',
              permissionProfile: 'repository-maintainer',
            ),
          ],
          workflows: [],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'owner-1',
          email: 'owner@example.com',
          role: 'owner',
          roleLabel: 'Owner',
          featureClaims: {},
          capabilities: {'tickets.read'},
        ),
      );
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SoftwareWorkshopScreen(
            controller: controller,
            roomId: 'main',
            repository: 'acme/product',
            projectId: 'project-1',
            onSelectionChanged: (_, _, _, _) {},
            onRoomChanged: (_, _, _) {},
            onManagePermissions: (_) {},
            onReviewSetup: () {},
            onConfigureProjects: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(projectRequests, hasLength(1));
    expect(projectRequests.single.queryParameters['projectId'], 'project-1');
    expect(
      projectRequests.single.queryParameters['repository'],
      'acme/product',
    );
    expect(find.text('Workshop could not be loaded'), findsNothing);
    expect(find.text('Your workshop is clear'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh pending tasks'));
    await tester.pumpAndSettle();

    expect(projectRequests, hasLength(2));
    expect(projectRequests.last.queryParameters['repository'], 'acme/product');
    expect(find.text('Workshop could not be loaded'), findsNothing);
    expect(find.text('Your workshop is clear'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

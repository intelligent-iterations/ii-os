import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/repositories/workshop_repository.dart';
import 'package:ii_os/services/api_client.dart';

void main() {
  test('Deploy, reset and status carry the selected repository', () async {
    final bodies = <Map<String, Object?>>[];
    final api = ApiClient(
      baseUrl: 'https://control.example/api',
      reportFailures: false,
      authTokenProvider: (_) async => 'synthetic-session',
      httpClient: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, Object?>);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    final repository = WorkshopApiRepository(api);
    await repository.deploy(
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      itemId: 'item-1',
      repository: 'acme/product',
    );
    await repository.reset(
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      itemId: 'item-1',
      repository: 'acme/product',
    );
    await repository.setStatus(
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      itemId: 'item-1',
      fieldId: 'status-field',
      optionId: 'todo',
      repository: 'acme/product',
    );
    expect(bodies, hasLength(3));
    expect(
      bodies.every((body) => body['repository'] == 'acme/product'),
      isTrue,
    );
  });
  test(
    'board read carries the selected repository to the project API',
    () async {
      Uri? projectRequest;
      final api = ApiClient(
        baseUrl: 'https://control.example/api',
        reportFailures: false,
        authTokenProvider: (_) async => 'synthetic-session',
        httpClient: MockClient((request) async {
          if (request.url.queryParameters['route'] ==
              'v1/workspaces/workspace-1/projects') {
            projectRequest = request.url;
            return http.Response(
              jsonEncode({
                'project': {
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

      await WorkshopApiRepository(api).board(
        workspaceId: 'workspace-1',
        projectId: 'PVT_workshop',
        repository: 'acme/product',
      );

      expect(projectRequest?.queryParameters['projectId'], 'PVT_workshop');
      expect(projectRequest?.queryParameters['repository'], 'acme/product');
    },
  );
}

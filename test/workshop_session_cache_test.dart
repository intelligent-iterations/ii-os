import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/workshop_session_cache.dart';

void main() {
  test('starts independent Workshop reads together', () async {
    final project = Completer<Map<String, dynamic>>();
    final profiles = Completer<Map<String, dynamic>>();
    final readiness = Completer<Map<String, dynamic>>();
    var projectStarted = false;
    var profilesStarted = false;
    var readinessStarted = false;

    final pending = loadWorkshopSessionSnapshot(
      loadProject: () {
        projectStarted = true;
        return project.future;
      },
      loadProfiles: () {
        profilesStarted = true;
        return profiles.future;
      },
      loadReadiness: () {
        readinessStarted = true;
        return readiness.future;
      },
    );

    expect(projectStarted, isTrue);
    expect(profilesStarted, isTrue);
    expect(readinessStarted, isTrue);

    project.complete(const {'project': <String, Object?>{}});
    profiles.complete(const {'profiles': <Object?>[]});
    readiness.complete(const {'ready': true});

    final snapshot = await pending;
    expect(snapshot.profileResponse, isNotNull);
    expect(snapshot.readinessResponse, isNotNull);
    expect(snapshot.automationError, isNull);
  });

  test('keeps a workshop snapshot for an exact workspace selection', () {
    final cache = WorkshopSessionCache(maxEntries: 2);
    const key = WorkshopSessionCacheKey(
      workspaceId: 'workspace-a',
      projectId: 'project-a',
      repository: 'owner/repository',
    );
    final snapshot = WorkshopSessionSnapshot(
      projectResponse: const {
        'project': {'id': 'project-a'},
      },
      profileResponse: const {'profiles': <Object?>[]},
      readinessResponse: const {'ready': true},
    );

    cache.put(key, snapshot);

    expect(cache.get(key), same(snapshot));
    expect(
      cache.get(
        const WorkshopSessionCacheKey(
          workspaceId: 'workspace-b',
          projectId: 'project-a',
          repository: 'owner/repository',
        ),
      ),
      isNull,
    );
  });

  test('evicts the least recently used workshop snapshot', () {
    final cache = WorkshopSessionCache(maxEntries: 2);
    const first = WorkshopSessionCacheKey(
      workspaceId: 'workspace',
      projectId: 'first',
      repository: 'owner/repository',
    );
    const second = WorkshopSessionCacheKey(
      workspaceId: 'workspace',
      projectId: 'second',
      repository: 'owner/repository',
    );
    const third = WorkshopSessionCacheKey(
      workspaceId: 'workspace',
      projectId: 'third',
      repository: 'owner/repository',
    );
    final snapshot = WorkshopSessionSnapshot(
      projectResponse: const {},
      profileResponse: const {},
      readinessResponse: const {},
    );

    cache.put(first, snapshot);
    cache.put(second, snapshot);
    expect(cache.get(first), same(snapshot));
    cache.put(third, snapshot);

    expect(cache.get(first), same(snapshot));
    expect(cache.get(second), isNull);
    expect(cache.get(third), same(snapshot));
  });

  test('projects a cached response into testable screen state', () {
    final value = WorkshopSessionPresentation.fromSnapshot(
      WorkshopSessionSnapshot(
        projectResponse: const {
          'project': {'id': 'project-a'},
          'agentDispatches': {
            'item-a': {'phase': 'queued'},
          },
        },
        profileResponse: const {
          'profiles': [
            {'id': 'profile-a'},
          ],
        },
        readinessResponse: const {},
        automationError: 'Readiness is unavailable.',
      ),
    );

    expect(value.project['id'], 'project-a');
    expect(value.agentDispatches['item-a']?['phase'], 'queued');
    expect(value.profiles.single.id, 'profile-a');
    expect(value.profilesVerified, isTrue);
    expect(value.automationReadiness, isNotNull);
    expect(value.automationError, 'Readiness is unavailable.');
  });

  test('requires every tenant selection before forming a cache key', () {
    expect(
      workshopSessionCacheKey(
        workspaceId: null,
        projectId: 'project-a',
        repository: 'owner/repository',
      ),
      isNull,
    );
    expect(
      workshopSessionCacheKey(
        workspaceId: 'workspace-a',
        projectId: 'project-a',
        repository: 'owner/repository',
      ),
      const WorkshopSessionCacheKey(
        workspaceId: 'workspace-a',
        projectId: 'project-a',
        repository: 'owner/repository',
      ),
    );
  });
}

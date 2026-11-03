import 'package:googleapis/storage/v1.dart' as storage;
import 'package:ii_os_functions/src/data_plane_connection_validator.dart';
import 'package:test/test.dart';

void main() {
  const workspaceId = '4b9ddf12-8458-4633-a43f-fc78839af384';
  const organizationId = '1493971f-a600-4d25-a0f2-1a4e18a92993';

  test('accepts durable media and one-day Ghost lifecycle rules', () {
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(workspaceId: workspaceId),
        workspaceId: workspaceId,
      ),
      isTrue,
    );
  });

  test('accepts fixed organization Ghost prefixes', () {
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(
          workspaceId: workspaceId,
          ghostPrefixes: [
            'organizations/$organizationId/ghost/',
            'organizations/$organizationId/ghost-source-assets/',
          ],
        ),
        workspaceId: '',
        organizationId: organizationId,
      ),
      isTrue,
    );
  });

  test('requires both isolated Ghost prefixes', () {
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(
          workspaceId: workspaceId,
          ghostPrefixes: ['workspaces/$workspaceId/ghost/'],
        ),
        workspaceId: workspaceId,
      ),
      isFalse,
    );
  });

  test('rejects a Ghost rule that also expires another prefix', () {
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(
          workspaceId: workspaceId,
          ghostPrefixes: [
            'workspaces/$workspaceId/ghost/',
            'workspaces/$workspaceId/ghost-source-assets/',
            'workspaces/$workspaceId/runs/',
          ],
        ),
        workspaceId: workspaceId,
      ),
      isFalse,
    );
  });

  test('does not treat the Ghost rule as durable retention', () {
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(workspaceId: workspaceId, includeDurableRule: false),
        workspaceId: workspaceId,
      ),
      isFalse,
    );
  });

  test('rejects retained object copies', () {
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(workspaceId: workspaceId, versioning: true),
        workspaceId: workspaceId,
      ),
      isFalse,
    );
    expect(
      bucketMediaLifecycleIsValid(
        _bucket(workspaceId: workspaceId, softDeleteSeconds: '604800'),
        workspaceId: workspaceId,
      ),
      isFalse,
    );
  });
}

storage.Bucket _bucket({
  required String workspaceId,
  bool includeDurableRule = true,
  List<String>? ghostPrefixes,
  bool versioning = false,
  String softDeleteSeconds = '0',
}) => storage.Bucket(
  versioning: storage.BucketVersioning(enabled: versioning),
  softDeletePolicy: storage.BucketSoftDeletePolicy(
    retentionDurationSeconds: softDeleteSeconds,
  ),
  lifecycle: storage.BucketLifecycle(
    rule: [
      if (includeDurableRule)
        storage.BucketLifecycleRule(
          action: storage.BucketLifecycleRuleAction(type: 'Delete'),
          condition: storage.BucketLifecycleRuleCondition(age: 30),
        ),
      storage.BucketLifecycleRule(
        action: storage.BucketLifecycleRuleAction(type: 'Delete'),
        condition: storage.BucketLifecycleRuleCondition(
          age: 1,
          matchesPrefix:
              ghostPrefixes ??
              [
                'workspaces/$workspaceId/ghost/',
                'workspaces/$workspaceId/ghost-source-assets/',
              ],
        ),
      ),
    ],
  ),
);

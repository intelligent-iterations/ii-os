import 'package:flutter_test/flutter_test.dart';

import '../tool/smoke_ownership.dart';

void main() {
  const runId = 'live-123';
  const ownerId = 'smoke-owner';

  Map<String, Object?> workspace({
    String markedRun = runId,
    String createdBy = ownerId,
    bool disposable = true,
  }) => {
    'fields': {
      'smokeRunId': {'stringValue': markedRun},
      'disposable': {'booleanValue': disposable},
      'createdBy': {'stringValue': createdBy},
    },
  };

  test('accepts a workspace owned by the current smoke run', () {
    expect(
      smokeOwnsWorkspaceDocument(
        workspace(),
        runId: runId,
        createdUserIds: const {ownerId},
      ),
      isTrue,
    );
  });

  test('rejects valuable or differently owned workspace data', () {
    for (final document in [
      workspace(markedRun: 'live-other'),
      workspace(createdBy: 'real-owner'),
      workspace(disposable: false),
      <String, Object?>{'fields': <String, Object?>{}},
    ]) {
      expect(
        smokeOwnsWorkspaceDocument(
          document,
          runId: runId,
          createdUserIds: const {ownerId},
        ),
        isFalse,
      );
    }
  });
}

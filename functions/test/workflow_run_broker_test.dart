import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workflow_run_broker.dart';
import 'package:ii_os_functions/src/workflow_run_store.dart';
import 'package:ii_os_functions/src/workflow_source_references.dart';
import 'package:test/test.dart';

void main() {
  group('workflow run verification', () {
    const claim = WorkflowRunClaim(
      requestId: 'request-123',
      repository: 'acme/media',
      repositoryId: 42,
      workflowRef:
          'acme/media/.github/workflows/ii-os-image.yaml@refs/heads/dev',
      commitSha: '0123456789abcdef0123456789abcdef01234567',
      runId: 9001,
      runAttempt: 1,
    );
    final job = <String, Object?>{
      'workflowPath': '.github/workflows/ii-os-image.yaml',
    };
    final run = <String, Object?>{
      'id': 9001,
      'run_attempt': 1,
      'event': 'workflow_dispatch',
      'head_sha': '0123456789abcdef0123456789abcdef01234567',
      'head_branch': 'dev',
      'path': '.github/workflows/ii-os-image.yaml',
      'display_title': 'ii-os image request-123',
      'repository': {'id': 42, 'full_name': 'acme/media'},
    };

    test('accepts the exact repository, wrapper, commit, and request', () {
      expect(
        () => validateClaimedGitHubRun(claim: claim, job: job, githubRun: run),
        returnsNormally,
      );
    });

    test('accepts the legacy GitHub path shape containing the ref', () {
      expect(
        () => validateClaimedGitHubRun(
          claim: claim,
          job: job,
          githubRun: {...run, 'path': '${run['path']}@dev'},
        ),
        returnsNormally,
      );
    });

    test('rejects a different repository or commit', () {
      for (final changed in [
        {...run, 'head_sha': List<String>.filled(40, 'f').join()},
        {...run, 'head_branch': 'other'},
        {...run, 'path': '.github/workflows/another.yaml'},
        {...run, 'display_title': 'unrelated-request-123'},
        {
          ...run,
          'repository': {'id': 43, 'full_name': 'acme/other'},
        },
      ]) {
        expect(
          () => validateClaimedGitHubRun(
            claim: claim,
            job: job,
            githubRun: changed,
          ),
          throwsA(
            isA<ApiError>().having(
              (error) => error.code,
              'code',
              'workflow_run_verification_failed',
            ),
          ),
        );
      }
    });
  });

  test('automatic selection chooses the first valid generated image', () {
    final artifact = firstGeneratedImageArtifact([
      {
        'path': 'workspaces/w/runs/job/video.mp4',
        'generation': '1',
        'content_type': 'video/mp4',
      },
      {
        'path': 'workspaces/w/runs/job/sheet.png',
        'generation': '2',
        'content_type': 'image/png',
      },
      {
        'path': 'workspaces/w/runs/job/other.png',
        'generation': '3',
        'content_type': 'image/png',
      },
    ]);

    expect(artifact?['path'], endsWith('sheet.png'));
    expect(artifact?['generation'], '2');
  });

  test('adds verified kind and role metadata to a source contract', () {
    const reference = WorkflowSourceReference(
      assetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
      inputField: 'reference_manifest',
      kind: 'video',
      role: 'source_video',
      ordinal: 0,
    );

    final contract = workflowSourceContract(const {
      'assetId': '33449737-9e39-4d53-8040-f39d5f7bc3ce',
      'contentType': 'video/mp4',
    }, reference);

    expect(contract['kind'], 'video');
    expect(contract['role'], 'source_video');
    expect(contract['ordinal'], 0);
  });

  test('rejects a source whose stored MIME type contradicts the manifest', () {
    expect(
      () => workflowSourceContract(
        const {'contentType': 'image/png'},
        const WorkflowSourceReference(
          assetId: '33449737-9e39-4d53-8040-f39d5f7bc3ce',
          inputField: 'reference_manifest',
          kind: 'video',
          role: 'source_video',
          ordinal: 0,
        ),
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'source_asset_kind_mismatch',
        ),
      ),
    );
  });
}

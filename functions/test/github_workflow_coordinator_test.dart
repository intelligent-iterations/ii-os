import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:ii_os_functions/src/github_workflow_coordinator.dart';
import 'package:ii_os_functions/src/job_run_store.dart';
import 'package:ii_os_functions/src/prompt_enhancer.dart';
import 'package:test/test.dart';

void main() {
  group('GitHub workflow reconciliation', () {
    test('Ghost dispatch excludes every validated generation input', () {
      const privateInputs = {
        'prompt': 'a private scene',
        'source_asset_id': 'private-source',
        'seed': '42',
        'model': 'z-image-turbo',
      };

      expect(
        GitHubWorkflowCoordinator.githubWorkflowDispatchInputs(
          inputs: privateInputs,
          requestId: 'request-123',
          ghostMode: true,
        ),
        {'ii_request_id': 'request-123', 'ii_payload_mode': 'claim'},
      );
      expect(
        GitHubWorkflowCoordinator.githubWorkflowDispatchInputs(
          inputs: privateInputs,
          requestId: 'request-123',
          ghostMode: false,
        ),
        {...privateInputs, 'ii_request_id': 'request-123'},
      );
    });

    test('Every dispatch bypasses external prompt enhancement', () {
      expect(
        resolvePromptEnhancementBypass(ghostMode: false, requested: null),
        PromptEnhancementBypass.userAuthored,
      );
      expect(
        resolvePromptEnhancementBypass(ghostMode: true, requested: null),
        PromptEnhancementBypass.ghostMode,
      );
      expect(
        resolvePromptEnhancementBypass(
          ghostMode: false,
          requested: PromptEnhancementBypass.imageToCharacter,
        ),
        PromptEnhancementBypass.imageToCharacter,
      );
    });

    test('preserves the visible user prompt at dispatch', () {
      const prompt = 'Put the rings in the hand.';
      final result = bypassPromptEnhancement(
        originalPrompt: prompt,
        context: const PromptEnhancementContext(
          workflowId: 'image-inpaint-qwen',
          targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
          requestType: 'image-to-image inpaint',
          attachedImageCount: 1,
        ),
        reason: PromptEnhancementBypass.userAuthored,
      );

      expect(result.prompt, prompt);
      expect(result.status, 'skipped');
      expect(result.skipReason, 'user_authored');
      expect(result.toMetadata()['skipReason'], 'user_authored');
    });

    test('appends the canonical reference map after the visible prompt', () {
      expect(
        appendPromptSuffix(
          'Jenny takes a sip.',
          suffix: 'Image 2 is the character reference for "Jenny".',
          maxLength: 1000,
        ),
        'Jenny takes a sip.\n\n'
        'Image 2 is the character reference for "Jenny".',
      );
    });

    test('bounds a visible prompt plus its reference map', () {
      expect(
        () => appendPromptSuffix(
          'Jenny takes a sip.',
          suffix: 'Image 2 is Jenny.',
          maxLength: 20,
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'invalid_job_input',
          ),
        ),
      );
    });

    test('does not semantically validate prompt language at dispatch', () {
      expect(
        appendPromptSuffix(
          'Jenny takes a sip.',
          suffix: 'Do not render a reference sheet.',
          maxLength: 1000,
        ),
        'Jenny takes a sip.\n\nDo not render a reference sheet.',
      );
    });

    test('matches only the dispatched wrapper and request ID', () {
      final submittedAt = DateTime.utc(2026, 7, 11, 12);
      final run = <String, Object?>{
        'event': 'workflow_dispatch',
        'display_title': 'ii-os image-create request-123',
        'path': '.github/workflows/image-create.yaml@dev',
        'created_at': '2026-07-11T12:00:02Z',
      };

      expect(
        matchesDispatchedRun(
          run,
          jobId: 'request-123',
          workflowPath: '.github/workflows/image-create.yaml',
          submittedAt: submittedAt,
        ),
        isTrue,
      );
      expect(
        matchesDispatchedRun(
          {...run, 'event': 'push'},
          jobId: 'request-123',
          workflowPath: '.github/workflows/image-create.yaml',
          submittedAt: submittedAt,
        ),
        isFalse,
      );
      expect(
        matchesDispatchedRun(
          run,
          jobId: 'request-456',
          workflowPath: '.github/workflows/image-create.yaml',
          submittedAt: submittedAt,
        ),
        isFalse,
      );
      expect(
        matchesDispatchedRun(
          {...run, 'path': '.github/workflows/image-create.yaml'},
          jobId: 'request-123',
          workflowPath: '.github/workflows/image-create.yaml',
          submittedAt: submittedAt,
        ),
        isTrue,
      );
    });

    test('repairs only synthetic unobserved-run failures', () {
      const base = <String, Object?>{
        'provider': 'github_actions',
        'status': 'failed',
        'errorCode': 'github_workflow_run_not_observed',
        'githubRunId': null,
      };

      expect(githubJobNeedsReconciliation(base), isTrue);
      expect(
        githubJobNeedsReconciliation({...base, 'githubRunId': 123}),
        isFalse,
      );
      expect(
        githubJobNeedsReconciliation({...base, 'errorCode': 'real_failure'}),
        isFalse,
      );
      expect(
        githubJobNeedsReconciliation({...base, 'status': 'dispatched'}),
        isTrue,
      );
      expect(
        githubJobNeedsReconciliation(base, retentionExpired: true),
        isFalse,
      );
    });

    test('looks up workflow runs from the dispatch window', () {
      expect(
        githubWorkflowRunLookupSince(DateTime.utc(2026, 7, 11, 12)),
        DateTime.utc(2026, 7, 11, 11, 58),
      );
      expect(
        githubWorkflowRunLookupUntil(DateTime.utc(2026, 7, 11, 12)),
        DateTime.utc(2026, 7, 11, 12, 30),
      );
      expect(githubWorkflowRunLookupSince(DateTime(0)), isNull);
      expect(githubWorkflowRunLookupUntil(DateTime(0)), isNull);
    });

    test('maps GitHub status and conclusion to product states', () {
      expect(githubRunStatus('queued', null), 'queued');
      expect(githubRunStatus('in_progress', null), 'running');
      expect(githubRunStatus('completed', 'success'), 'completed');
      expect(githubRunStatus('completed', 'cancelled'), 'cancelled');
      expect(githubRunStatus('completed', 'timed_out'), 'failed');
      expect(
        githubRunStatus('in_progress', null, cancellationRequested: true),
        'cancelling',
      );
      expect(
        githubRunStatus('completed', 'success', cancellationRequested: true),
        'completed',
      );
    });

    test('expires an old unobserved GitHub workflow job', () {
      final submittedAt = DateTime.utc(2026, 7, 20, 22, 35);
      final job = <String, Object?>{
        'provider': 'github_actions',
        'status': 'dispatched',
        'submittedAt': submittedAt.toIso8601String(),
      };

      expect(
        shouldExpireUnobservedGitHubJob(
          job,
          now: submittedAt.add(const Duration(minutes: 29, seconds: 59)),
        ),
        isFalse,
      );
      expect(
        shouldExpireUnobservedGitHubJob(
          job,
          now: submittedAt.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
      expect(
        shouldExpireUnobservedGitHubJob({
          ...job,
          'status': 'completed',
        }, now: submittedAt.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test(
      'requires a workspace GitHub installation before repository access',
      () async {
        final client = GitHubClient(appId: '', privateKey: '');
        final workspace = Workspace(
          id: 'workspace-1',
          name: 'Example',
          environment: 'dev',
          githubInstallationId: null,
          repositories: const ['acme-co/example-app'],
          projects: const [],
          workflows: const [],
          artifactStorage: null,
        );

        await expectLater(
          client.readWorkflowCatalogFile(workspace, 'acme-co/example-app'),
          throwsA(
            isA<ApiError>()
                .having((error) => error.status, 'status', 409)
                .having(
                  (error) => error.code,
                  'code',
                  'github_installation_required',
                ),
          ),
        );
      },
    );
  });
}

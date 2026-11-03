import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/prompt_guide_store.dart';
import 'package:test/test.dart';

void main() {
  group('validatedPromptGuideBody', () {
    test('trims and accepts real guide text', () {
      expect(
        validatedPromptGuideBody('  Describe the finished image.  '),
        'Describe the finished image.',
      );
    });

    test('refuses an empty guide rather than silently blanking it', () {
      // A blank body would leave the enhancer with no rules at all, which is a
      // worse outcome than the default it was replacing.
      for (final body in ['', '   ', '\n\t ']) {
        expect(
          () => validatedPromptGuideBody(body),
          throwsA(
            isA<ApiError>().having(
              (error) => error.code,
              'code',
              'invalid_prompt_guide',
            ),
          ),
          reason: 'accepted ${body.length} blank characters',
        );
      }
    });

    test('refuses a guide longer than every rewrite can carry', () {
      expect(
        () => validatedPromptGuideBody('x' * 40001),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'invalid_prompt_guide',
          ),
        ),
      );
      expect(validatedPromptGuideBody('x' * 40000).length, 40000);
    });
  });

  test('an organization and a workspace id can never collide', () {
    // Both tiers store under one collection, so the scope has to be part of
    // the key -- an organization and a workspace that happen to share an id
    // would otherwise overwrite each other's guides.
    expect(
      PromptGuideStore.documentId(PromptGuideScope.organization, 'shared'),
      isNot(PromptGuideStore.documentId(PromptGuideScope.workspace, 'shared')),
    );
    expect(
      PromptGuideStore.documentId(PromptGuideScope.workspace, 'ws-1'),
      'workspace_ws-1',
    );
  });

  test('scope parses only the names it writes', () {
    expect(PromptGuideScope.tryParse('workspace'), PromptGuideScope.workspace);
    expect(
      PromptGuideScope.tryParse('organization'),
      PromptGuideScope.organization,
    );
    expect(PromptGuideScope.tryParse('project'), isNull);
    expect(PromptGuideScope.tryParse(''), isNull);
  });

  test('a stored override serialises what a client may see', () {
    final override = PromptGuideOverride(
      guideId: 'chatterbox-speech',
      body: 'Read it as written.',
      version: 3,
      updatedBy: 'uid-1',
      updatedAt: DateTime.utc(2026, 8, 21, 12, 30),
    );

    expect(override.toJson(), {
      'guideId': 'chatterbox-speech',
      'body': 'Read it as written.',
      'version': 3,
      'updatedBy': 'uid-1',
      'updatedAt': '2026-08-21T12:30:00.000Z',
    });
  });

  test('a revision says what happened, not just what it holds', () {
    final revision = PromptGuideRevision(
      id: 'rev-1',
      guideId: 'ace-step-lyrics',
      body: '[Verse]',
      version: 2,
      change: PromptGuideChange.restored,
      createdBy: 'uid-2',
      createdAt: DateTime.utc(2026, 8, 21),
      note: 'Restored version 1',
    );

    expect(revision.toJson()['change'], 'restored');
    expect(revision.toJson()['note'], 'Restored version 1');
    expect(revision.toJson()['version'], 2);
  });
}

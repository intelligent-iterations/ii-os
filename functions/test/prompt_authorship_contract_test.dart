import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('model prompt rewriting is reachable only from the preview route', () {
    final callSites = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file.readAsStringSync().contains('promptEnhancer.enhance('),
        )
        .map((file) => file.path)
        .toList();

    expect(callSites, ['lib/src/api_prompt_enhancement_route.dart']);
  });

  test('generation dispatch has no prompt rewriter or semantic gate', () {
    final coordinator = File(
      'lib/src/github_workflow_coordinator.dart',
    ).readAsStringSync();
    expect(coordinator, isNot(contains('DeepSeekPromptEnhancer')));
    expect(coordinator, isNot(contains('PromptGuideStore')));
    expect(coordinator, isNot(contains('hasNegativePromptLanguage')));
  });
}

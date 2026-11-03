import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/repositories/prompt_enhancement_repository.dart';
import 'package:ii_os/state/prompt_enhancement_fields.dart';

import 'prompt_enhancement_stubs.dart';

void main() {
  test('a kept rewrite is tracked for its own workflow field', () async {
    final fields = PromptEnhancementFields(
      repository: StubPromptEnhancements(),
      workspaceId: 'ws_test',
    );

    await fields.enhance(
      const PromptEnhancementRequest(
        prompt: 'The harbour lights',
        workflowId: 'song-create-acestep-xl-sft',
        targetModel: 'ACE-Step 1.5',
        field: 'lyrics',
        modality: 'lyrics',
        maxLength: 60000,
      ),
    );

    expect(fields.keptEnhancedTextFor('lyrics'), isTrue);
    expect(fields.keptEnhancedTextFor('prompt'), isFalse);
  });
}

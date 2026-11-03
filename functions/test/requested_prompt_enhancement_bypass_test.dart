import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/prompt_enhancer.dart';
import 'package:ii_os_functions/src/requested_prompt_enhancement_bypass.dart';
import 'package:test/test.dart';

void main() {
  test('accepts only the user-reviewed prompt bypass from a client', () {
    expect(requestedPromptEnhancementBypass(null), isNull);
    expect(
      requestedPromptEnhancementBypass('user_enhanced'),
      PromptEnhancementBypass.userEnhanced,
    );

    for (final value in const [
      'ghost_mode',
      'character_prompt_builder',
      'image_to_character',
      'unknown',
      true,
    ]) {
      expect(
        () => requestedPromptEnhancementBypass(value),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'invalid_prompt_enhancement_bypass',
          ),
        ),
        reason: 'client value $value',
      );
    }
  });
}

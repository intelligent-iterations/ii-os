import 'api_error.dart';
import 'prompt_enhancer.dart';

/// Parses the only prompt-enhancement bypass a client is allowed to request.
///
/// Every other reason is a server-side conclusion. Accepting one from a
/// client would let it turn enhancement off by pretending to be an internal
/// generation path.
PromptEnhancementBypass? requestedPromptEnhancementBypass(Object? value) {
  if (value == null) return null;
  if (value is String &&
      value == PromptEnhancementBypass.userEnhanced.metadataValue) {
    return PromptEnhancementBypass.userEnhanced;
  }
  throw const ApiError(
    400,
    'invalid_prompt_enhancement_bypass',
    'That prompt enhancement bypass reason is not one a client may request.',
  );
}

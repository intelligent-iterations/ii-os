import 'api_error.dart';

/// What a workspace admin submitted on the prompt-enhancement form.
///
/// [apiKey] is deliberately separated from the rest: everything else on this
/// object is written to the workspace document, and the key never is.
final class PromptEnhancementSubmission {
  const PromptEnhancementSubmission({
    required this.enabled,
    required this.apiKeySecretVersion,
    required this.apiKey,
    required this.clearApiKey,
  });

  final bool enabled;
  final String apiKeySecretVersion;

  /// The pasted key, or empty when the form left the field untouched. An
  /// untouched field means "keep whatever is installed", not "remove it" --
  /// the form cannot show the current key, so it cannot echo it back either.
  final String apiKey;
  final bool clearApiKey;

  bool get hasPastedKey => apiKey.isNotEmpty;
}

/// Parses and validates the prompt-enhancement section of a workspace update.
PromptEnhancementSubmission parsePromptEnhancement(Object? value) {
  if (value is! Map) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement',
      'Prompt enhancement configuration is invalid.',
    );
  }
  final json = value.cast<String, Object?>();
  const known = {
    'provider',
    'enabled',
    'apiKeySecretVersion',
    'apiKey',
    'clearApiKey',
    'hasApiKey',
    'apiKeyLast4',
  };
  if (json.keys.any((key) => !known.contains(key))) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement',
      'Prompt enhancement configuration has an unknown field.',
    );
  }
  final provider = json['provider'];
  final enabled = json['enabled'];
  final secretVersion = json['apiKeySecretVersion'];
  if (provider != 'deepseek' || enabled is! bool || secretVersion is! String) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement',
      'DeepSeek prompt enhancement configuration is invalid.',
    );
  }
  final normalizedSecretVersion = secretVersion.trim();
  if (normalizedSecretVersion.isNotEmpty &&
      !googleSecretVersionResource.hasMatch(normalizedSecretVersion)) {
    throw const ApiError(
      400,
      'invalid_deepseek_secret',
      'Use a Google Secret Manager version resource ending in a number or latest.',
    );
  }
  final rawKey = json['apiKey'];
  if (rawKey != null && rawKey is! String) {
    throw const ApiError(
      400,
      'invalid_deepseek_api_key',
      'Paste the DeepSeek API key exactly as DeepSeek issued it.',
    );
  }
  final apiKey = (rawKey as String? ?? '').trim();
  if (apiKey.isNotEmpty && (apiKey.length < 8 || apiKey.length > 4096)) {
    throw const ApiError(
      400,
      'invalid_deepseek_api_key',
      'Paste the DeepSeek API key exactly as DeepSeek issued it.',
    );
  }
  final clearApiKey = json['clearApiKey'];
  if (clearApiKey != null && clearApiKey is! bool) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement',
      'Prompt enhancement configuration is invalid.',
    );
  }
  if (apiKey.isNotEmpty && clearApiKey == true) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement',
      'Choose either a new API key or removing the stored one.',
    );
  }
  return PromptEnhancementSubmission(
    enabled: enabled,
    apiKeySecretVersion: normalizedSecretVersion,
    apiKey: apiKey,
    clearApiKey: clearApiKey == true,
  );
}

/// The prompt-enhancement fields to persist on the workspace document.
///
/// Takes the credential state as arguments rather than reading it off the
/// submission, so the only way to record `hasApiKey: true` is to have actually
/// stored a key first.
Map<String, Object?> promptEnhancementDocument({
  required PromptEnhancementSubmission submission,
  required bool hasApiKey,
  required String apiKeyLast4,
}) {
  if (submission.enabled &&
      !hasApiKey &&
      submission.apiKeySecretVersion.isEmpty) {
    throw const ApiError(
      400,
      'missing_deepseek_credential',
      'Paste a DeepSeek API key or name a Secret Manager version before turning enhancement on.',
    );
  }
  return {
    'provider': 'deepseek',
    'enabled': submission.enabled,
    'apiKeySecretVersion': submission.apiKeySecretVersion,
    'hasApiKey': hasApiKey,
    'apiKeyLast4': hasApiKey ? apiKeyLast4 : '',
  };
}

/// Validates the already-sanitised document on its way into Firestore.
///
/// Fails closed on a pasted key: reaching the store still carrying `apiKey`
/// means the route did not strip it, and the next write would put a live
/// credential on the document the API serialises back to clients.
Map<String, Object?>? validatedPromptEnhancement(Object? value) {
  if (value == null) return null;
  if (value is Map && value.containsKey('apiKey')) {
    throw const ApiError(
      500,
      'unstored_prompt_enhancement_key',
      'The API key was not stored before the workspace was updated.',
    );
  }
  final submission = parsePromptEnhancement(value);
  final json = (value as Map).cast<String, Object?>();
  return promptEnhancementDocument(
    submission: submission,
    hasApiKey: json['hasApiKey'] == true,
    apiKeyLast4: json['apiKeyLast4'] as String? ?? '',
  );
}

final RegExp googleSecretVersionResource = RegExp(
  r'^projects/[A-Za-z0-9][A-Za-z0-9._-]{0,127}/secrets/'
  r'[A-Za-z0-9_-]{1,255}/versions/(?:latest|[1-9][0-9]*)$',
);

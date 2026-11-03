/// Builds the prompt-enhancement portion of a workspace settings update.
///
/// Only one credential source may be effective. Selecting Secret Manager
/// therefore retires a previously pasted key; otherwise the stored key would
/// continue to win on the server while the UI claimed the secret was in use.
Map<String, Object?> promptEnhancementSettingsChange({
  required bool enabled,
  required bool usesSecretManager,
  required String secretVersion,
  required String pastedApiKey,
  required bool hasStoredPastedKey,
  required bool removeStoredPastedKey,
}) {
  final apiKey = usesSecretManager ? '' : pastedApiKey.trim();
  final clearApiKey =
      apiKey.isEmpty &&
      (removeStoredPastedKey || (usesSecretManager && hasStoredPastedKey));
  return {
    'provider': 'deepseek',
    'enabled': enabled,
    'apiKeySecretVersion': usesSecretManager ? secretVersion.trim() : '',
    if (apiKey.isNotEmpty && !usesSecretManager) 'apiKey': apiKey,
    if (clearApiKey) 'clearApiKey': true,
  };
}

/// The non-secret identifier to show after [change] has been accepted.
String installedPastedKeyLast4AfterSave(
  Map<String, Object?> change, {
  required String current,
}) {
  final apiKey = (change['apiKey'] as String? ?? '').trim();
  if (apiKey.isNotEmpty) {
    final start = apiKey.length > 4 ? apiKey.length - 4 : 0;
    return apiKey.substring(start);
  }
  if (change['clearApiKey'] == true) return '';
  return current;
}

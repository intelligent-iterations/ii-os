import 'dart:convert';

/// Secret Manager payloads attest the purpose and both ownership scopes.
/// The broker can access secrets from multiple tenants; a resource path alone
/// never authorizes using its contents as a provider credential.
String? boundPromptEnhancementKey(
  String payload, {
  required String organizationId,
  required String workspaceId,
}) {
  if (organizationId.isEmpty ||
      workspaceId.isEmpty ||
      utf8.encode(payload).length > 16 * 1024) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  const fields = {
    'schemaVersion',
    'purpose',
    'organizationId',
    'workspaceId',
    'apiKey',
  };
  if (decoded is! Map<String, Object?> ||
      decoded.length != fields.length ||
      decoded.keys.any((key) => !fields.contains(key)) ||
      decoded['schemaVersion'] != 1 ||
      decoded['purpose'] != 'ii-os-deepseek' ||
      decoded['organizationId'] != organizationId ||
      decoded['workspaceId'] != workspaceId) {
    return null;
  }
  final value = decoded['apiKey'];
  if (value is! String) return null;
  final key = value.trim();
  if (key.length < 8 ||
      key.length > 4096 ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(key)) {
    return null;
  }
  return key;
}

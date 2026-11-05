import 'dart:convert';

import 'package:googleapis/secretmanager/v1.dart' as secretmanager;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'creative_surface.dart';
import 'domain.dart';
import 'model_bibles.dart';
import 'prompt_enhancement_secret.dart';

part 'prompt_enhancer_contracts.dart';

final Uri deepSeekChatCompletionsUri = Uri.https(
  'api.deepseek.com',
  '/chat/completions',
);

typedef SecretVersionReader = Future<String> Function(String resourceName);

/// Reads the DeepSeek key a workspace pasted into ii-os, or null when it has
/// none. Kept separate from [SecretVersionReader] so the two key sources fail
/// independently: a broken Secret Manager grant must not look like a missing
/// pasted key, and vice versa.
typedef StoredApiKeyReader = Future<String?> Function(String workspaceId);

enum PromptEnhancementBypass {
  characterPromptBuilder('character_prompt_builder'),
  imageToCharacter('image_to_character'),
  ghostMode('ghost_mode'),

  /// Dispatch uses the text currently visible to the person. Rewriting is an
  /// explicit preview action, never an implicit part of starting a job.
  userAuthored('user_authored'),

  /// The person already ran this text through the enhancer and kept the
  /// result. Enhancing it again at dispatch would rewrite a prompt they
  /// reviewed and accepted, which is the one edit they did not ask for.
  userEnhanced('user_enhanced');

  const PromptEnhancementBypass(this.metadataValue);

  final String metadataValue;

  static PromptEnhancementBypass? tryParse(String value) {
    for (final bypass in PromptEnhancementBypass.values) {
      if (bypass.metadataValue == value) return bypass;
    }
    return null;
  }
}

enum PromptEnhancementPurpose { general, storyboardPanel }

final class PromptEnhancementResult {
  const PromptEnhancementResult({
    required this.prompt,
    required this.status,
    required this.targetModel,
    required this.bible,
    required this.modality,
    this.modelSpecific = true,
    this.guideCustomized = false,
    this.fallbackReason,
    this.skipReason,
  });

  final String prompt;
  final String status;
  final String targetModel;
  final String bible;
  final CreativeModality modality;

  /// False when the guide applied was a modality fallback rather than one
  /// written for this model.
  final bool modelSpecific;

  /// True when an administrator's edited guide steered this rewrite.
  ///
  /// On the run because when a generation comes out strangely the first
  /// question is whether a guide somebody changed is what steered it, and the
  /// job metadata is the only place that can answer after the fact.
  final bool guideCustomized;
  final String? fallbackReason;
  final String? skipReason;

  Map<String, Object?> toMetadata() => {
    'provider': 'deepseek',
    'providerModel': deepSeekPromptEnhancementModel,
    'status': status,
    'targetModel': targetModel,
    'bible': bible,
    'modality': modality.value,
    'modelSpecific': modelSpecific,
    'guideCustomized': guideCustomized,
    if (fallbackReason != null) 'fallbackReason': fallbackReason,
    if (skipReason != null) 'skipReason': skipReason,
  };
}

final class PromptEnhancementContext {
  const PromptEnhancementContext({
    required this.workflowId,
    required this.targetModel,
    required this.requestType,
    required this.attachedImageCount,
    this.field = 'prompt',
    this.modality,
    this.purpose = PromptEnhancementPurpose.general,
    this.library = PromptGuideLibrary.defaults,
  });

  factory PromptEnhancementContext.fromWorkflow({
    required String workflowId,
    required String targetModel,
    required Map<String, String> input,
    String field = 'prompt',
    Iterable<String> outputKinds = const <String>[],
    PromptEnhancementPurpose purpose = PromptEnhancementPurpose.general,
    PromptGuideLibrary library = PromptGuideLibrary.defaults,
  }) {
    final imageCount = countAttachedImages(input);
    final normalized = workflowId.toLowerCase();
    final h3Mode = _referenceManifestMode(input['reference_manifest']);
    final requestType = switch (h3Mode) {
      'video_edit' => 'full-reference video editing',
      'video_continue' => 'full-reference video continuation',
      'reference_to_video' => 'full-reference video generation',
      'first_frame_to_video' ||
      'last_frame_to_video' ||
      'first_last_frame_to_video' => 'image-to-video',
      _ => switch (normalized) {
        _ when field == 'lyrics' => 'song lyrics',
        _ when normalized.contains('narration') || normalized.contains('tts') =>
          'text-to-speech narration',
        _ when normalized.contains('song') || normalized.contains('music') =>
          'text-to-music generation',
        _ when normalized.contains('inpaint') => 'image-to-image inpaint',
        _ when normalized.contains('image-to-video') => 'image-to-video',
        _ when normalized.contains('text-to-video') => 'text-to-video',
        _ when normalized.contains('image-edit') => 'image-to-image edit',
        _ when normalized.contains('video') && imageCount > 0 =>
          'image-to-video',
        _ when normalized.contains('video') => 'text-to-video',
        _ when imageCount > 0 => 'image-conditioned generation',
        _ when normalized.contains('image') => 'text-to-image generation',
        _ => 'text-only generation',
      },
    };
    return PromptEnhancementContext(
      workflowId: workflowId,
      targetModel: targetModel,
      requestType: requestType,
      attachedImageCount: imageCount,
      field: field,
      modality: creativeModalityFor(
        field: field,
        workflowId: workflowId,
        model: targetModel,
        outputKinds: outputKinds,
        attachedImageCount: imageCount,
      ),
      purpose: purpose,
      library: library,
    );
  }

  final String workflowId;
  final String targetModel;
  final String requestType;
  final int attachedImageCount;

  /// The workflow input this text belongs to -- `prompt`, `lyrics`, `text`.
  final String field;
  final CreativeModality? modality;
  final PromptEnhancementPurpose purpose;

  /// The guide text in force, already merged across organization and workspace.
  final PromptGuideLibrary library;

  ModelBibleSelection get bible => modelBibleSelectionFor(
    targetModel,
    workflowId: workflowId,
    field: field,
    modality: modality,
    attachedImageCount: attachedImageCount,
    library: library,
  );
}

String? _referenceManifestMode(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    return decoded is Map && decoded['mode'] is String
        ? decoded['mode']! as String
        : null;
  } on FormatException {
    return null;
  }
}

final class DeepSeekPromptEnhancer {
  DeepSeekPromptEnhancer({
    http.Client? httpClient,
    SecretVersionReader? secretReader,
    this._storedKeyReader,
  }) : _http = httpClient ?? http.Client(),
       _secretReader = secretReader ?? readGoogleSecretVersion;

  final http.Client _http;
  final SecretVersionReader _secretReader;
  final StoredApiKeyReader? _storedKeyReader;

  PromptEnhancementResult bypass({
    required String originalPrompt,
    required PromptEnhancementContext context,
    required PromptEnhancementBypass reason,
  }) {
    return bypassPromptEnhancement(
      originalPrompt: originalPrompt.trim(),
      context: context,
      reason: reason,
    );
  }

  Future<PromptEnhancementResult> enhance({
    required Workspace workspace,
    required String originalPrompt,
    required PromptEnhancementContext context,
    required int maxPromptLength,
  }) async {
    final prompt = originalPrompt.trim();
    final bible = context.bible;
    final config = workspace.promptEnhancement;
    if (config == null || !config.enabled) {
      return _original(prompt, context, bible, status: 'disabled');
    }

    final apiKey = await _apiKey(workspace, config);
    if (apiKey == null) {
      return _original(
        prompt,
        context,
        bible,
        status: 'fallback',
        reason: 'key_unavailable',
      );
    }

    try {
      final response = await _http
          .post(
            deepSeekChatCompletionsUri,
            headers: {
              'authorization': 'Bearer $apiKey',
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(
              buildDeepSeekPromptRequest(
                originalPrompt: prompt,
                context: context,
              ),
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _original(
          prompt,
          context,
          bible,
          status: 'fallback',
          reason: 'provider_unavailable',
        );
      }
      final enhanced = enhancedPromptFromResponse(response.body);
      if (enhanced == null || enhanced.length > maxPromptLength) {
        return _original(
          prompt,
          context,
          bible,
          status: 'fallback',
          reason: 'invalid_response',
        );
      }
      return PromptEnhancementResult(
        prompt: enhanced,
        status: 'enhanced',
        targetModel: context.targetModel,
        bible: bible.id,
        modality: bible.modality,
        modelSpecific: bible.isModelSpecific,
        guideCustomized: bible.customized,
      );
    } on Object {
      return _original(
        prompt,
        context,
        bible,
        status: 'fallback',
        reason: 'provider_unavailable',
      );
    }
  }

  /// Resolves the DeepSeek key, preferring one pasted into ii-os over a Secret
  /// Manager version, and returning null when neither yields a usable value.
  Future<String?> _apiKey(
    Workspace workspace,
    PromptEnhancementConfig config,
  ) async {
    final storedKeyReader = _storedKeyReader;
    if (config.hasApiKey && storedKeyReader != null) {
      try {
        final stored = (await storedKeyReader(workspace.id))?.trim() ?? '';
        if (_usableKey(stored)) return stored;
      } on Object {
        // Fall through to the Secret Manager path below.
      }
    }
    if (config.apiKeySecretVersion.isEmpty) return null;
    try {
      final secret = (await _secretReader(config.apiKeySecretVersion)).trim();
      return boundPromptEnhancementKey(
        secret,
        organizationId: workspace.organizationId,
        workspaceId: workspace.id,
      );
    } on Object {
      return null;
    }
  }
}

PromptEnhancementResult bypassPromptEnhancement({
  required String originalPrompt,
  required PromptEnhancementContext context,
  required PromptEnhancementBypass reason,
}) {
  final bible = context.bible;
  return PromptEnhancementResult(
    prompt: originalPrompt,
    status: 'skipped',
    targetModel: context.targetModel,
    bible: bible.id,
    modality: bible.modality,
    modelSpecific: bible.isModelSpecific,
    guideCustomized: bible.customized,
    skipReason: reason.metadataValue,
  );
}

bool _usableKey(String value) => value.isNotEmpty && value.length <= 4096;

Future<String> readGoogleSecretVersion(String resourceName) async {
  final client = await clientViaApplicationDefaultCredentials(
    scopes: [secretmanager.SecretManagerApi.cloudPlatformScope],
  );
  try {
    final response = await secretmanager.SecretManagerApi(client)
        .projects
        .secrets
        .versions
        .access(resourceName)
        .timeout(const Duration(seconds: 10));
    final encoded = response.payload?.data;
    if (encoded == null || encoded.isEmpty) return '';
    return utf8.decode(base64Decode(encoded)).trim();
  } finally {
    client.close();
  }
}

Map<String, Object?> buildDeepSeekPromptRequest({
  required String originalPrompt,
  required PromptEnhancementContext context,
}) {
  final selection = context.bible;
  final imageLabel = context.attachedImageCount == 1 ? 'image' : 'images';
  final storyboardRules =
      context.purpose == PromptEnhancementPurpose.storyboardPanel &&
          selection.modality.isDirection
      ? _storyboardRules
      : '';
  return {
    'model': deepSeekPromptEnhancementModel,
    'messages': [
      {
        'role': 'system',
        'content':
            '''
${selection.guide.trim()}

${_contractFor(selection.modality)}$storyboardRules
'''
                .trim(),
      },
      {
        'role': 'user',
        'content': _userMessage(
          originalPrompt: originalPrompt,
          context: context,
          selection: selection,
          imageLabel: imageLabel,
        ),
      },
    ],
    'thinking': {'type': 'disabled'},
    'temperature': 0.2,
    'max_tokens': 4096,
    'stream': false,
  };
}

String _userMessage({
  required String originalPrompt,
  required PromptEnhancementContext context,
  required ModelBibleSelection selection,
  required String imageLabel,
}) {
  final attachments = selection.modality.isDirection
      ? '''
Attached images in the target generation request: ${context.attachedImageCount} $imageLabel.

The attachment count is available while the image pixels and their contents are
unavailable. Ground visual details in the original prompt and preserve
image-relative wording when it is useful to the target model.
'''
      : '';
  final verb = selection.modality.isDirection
      ? '''
Rewrite this original prompt so it is excellent for the target model, following
the system guide.'''
      : '''
Rewrite this text for the target model following the system guide, keeping the
author's words and meaning intact.''';
  return '''
Target model: ${context.targetModel}
Request type: ${context.requestType}
Field: ${context.field}
${attachments.trim()}

$verb The original text is this JSON string:
${jsonEncode(originalPrompt)}
'''
      .trim();
}

/// The rewriting contract, which differs by modality far more than the guides
/// do. Direction fields may be reorganized while spoken and sung words need
/// stricter preservation, but neither path judges or rejects prompt content.
String _contractFor(CreativeModality modality) =>
    modality.isDirection ? _directionContract : _verbatimContract;

String? enhancedPromptFromResponse(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, Object?>) return null;
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final choice = (choices.first as Map).cast<String, Object?>();
    final message = choice['message'];
    if (message is! Map) return null;
    final content = message['content'];
    final prompt = content is String ? _plainPrompt(content) : null;
    return prompt;
  } on FormatException {
    return null;
  }
}

bool hasNegativePromptLanguage(String prompt) {
  final directions = prompt
      .replaceAll(RegExp(r'"(?:\\.|[^"\\])*"'), ' ')
      .replaceAll(RegExp(r'\u201C[^\u201D]*\u201D'), ' ');
  return RegExp(
    r'''\b(?:no|not|without|free\s+of|avoid|avoiding|exclude|excluding|never|do\s+not|don't|negative[_ -]prompt(?:s|ing)?)\b''',
    caseSensitive: false,
  ).hasMatch(directions);
}

int countAttachedImages(Map<String, String> input) {
  var count = 0;
  for (final entry in input.entries) {
    if (entry.key == 'reference_manifest') {
      count += _manifestImageCount(entry.value);
      continue;
    }
    if (!_isImageAttachmentKey(entry.key) || entry.value.trim().isEmpty) {
      continue;
    }
    count += _attachmentValueCount(entry.value);
  }
  return count;
}

int _manifestImageCount(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) return 0;
    final references = decoded['references'];
    if (references is! List<Object?>) return 0;
    return references.where((reference) {
      return reference is Map && reference['kind'] == 'image';
    }).length;
  } on FormatException {
    return 0;
  }
}

bool _isImageAttachmentKey(String key) {
  final normalized = key.toLowerCase();
  return normalized.startsWith('source_asset_id') ||
      normalized.startsWith('source_image') ||
      normalized.startsWith('reference_image') ||
      normalized == 'image_urls';
}

int _attachmentValueCount(String value) {
  final normalized = value.trim();
  if (normalized.startsWith('[')) {
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is List<Object?>) {
        return decoded
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .length;
      }
    } on FormatException {
      // A malformed list still represents one declared workflow input.
    }
  }
  return 1;
}

PromptEnhancementResult _original(
  String prompt,
  PromptEnhancementContext context,
  ModelBibleSelection bible, {
  required String status,
  String? reason,
}) => PromptEnhancementResult(
  prompt: prompt,
  status: status,
  targetModel: context.targetModel,
  bible: bible.id,
  modality: bible.modality,
  modelSpecific: bible.isModelSpecific,
  guideCustomized: bible.customized,
  fallbackReason: reason,
);

String? _plainPrompt(String value) {
  var prompt = value.trim();
  if (prompt.startsWith('```') && prompt.endsWith('```')) {
    prompt = prompt.substring(3, prompt.length - 3).trim();
    final firstLine = prompt.indexOf('\n');
    if (firstLine >= 0 &&
        RegExp(
          r'^[A-Za-z0-9_-]{1,20}$',
        ).hasMatch(prompt.substring(0, firstLine).trim())) {
      prompt = prompt.substring(firstLine + 1).trim();
    }
  }
  prompt = prompt.replaceFirst(
    RegExp(r'^(?:enhanced\s+prompt|prompt)\s*:\s*', caseSensitive: false),
    '',
  );
  if (prompt.length >= 2 &&
      ((prompt.startsWith('"') && prompt.endsWith('"')) ||
          (prompt.startsWith("'") && prompt.endsWith("'")) ||
          (prompt.startsWith('\u201c') && prompt.endsWith('\u201d')))) {
    prompt = prompt.substring(1, prompt.length - 1).trim();
  }
  return prompt.isEmpty ? null : prompt;
}

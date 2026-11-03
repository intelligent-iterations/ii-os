import '../models/models.dart';
import '../services/api_client.dart';

/// One creative field offered to the rewriter.
///
/// [maxLength] is the budget of the workflow input this text is destined for,
/// and the caller supplies it because only the caller knows which field that
/// is. The budgets differ by an order of magnitude -- 4,000 characters for a
/// song description against 30,000 for its lyrics -- and a rewrite past the
/// budget is one the dispatch would reject.
final class PromptEnhancementRequest {
  const PromptEnhancementRequest({
    required this.prompt,
    required this.workflowId,
    required this.targetModel,
    required this.field,
    required this.maxLength,
    this.modality,
    this.attachedImageCount = 0,
    this.storyboardPanel = false,
  });

  final String prompt;
  final String workflowId;
  final String targetModel;

  /// The workflow input this text belongs to: `prompt`, `lyrics`, `text`.
  final String field;
  final int maxLength;

  /// Names the modality when the workflow id alone would not settle it.
  final String? modality;
  final int attachedImageCount;

  /// True when the text belongs to a storyboard panel, which adds continuity
  /// rules the rewrite has to follow to keep a cast recognisable across panels.
  final bool storyboardPanel;

  JsonMap body() => {
    'prompt': prompt,
    'workflowId': workflowId,
    'targetModel': targetModel,
    'field': field,
    'maxLength': maxLength,
    'modality': ?modality,
    'attachedImageCount': attachedImageCount,
    if (storyboardPanel) 'purpose': 'storyboard_panel',
  };
}

/// What came back, including whether anything actually changed.
final class PromptEnhancementResult {
  const PromptEnhancementResult({
    required this.prompt,
    required this.status,
    required this.bible,
    required this.modality,
    required this.modelSpecific,
    required this.targetModel,
    this.fallbackReason,
  });

  /// `enhanced`, `fallback`, `disabled`, or `skipped`.
  final String status;

  /// The rewritten text, or the original when nothing changed.
  final String prompt;

  /// The guide that was applied, e.g. `chatterbox-speech`.
  final String bible;
  final String modality;

  /// False when the guide was a modality fallback, not one written for this
  /// model. Worth telling the person: the rewrite is still grounded, but
  /// nobody has written rules for their exact model.
  final bool modelSpecific;
  final String targetModel;
  final String? fallbackReason;

  bool get changed => status == 'enhanced';
}

/// The single owner of `v1/workspaces/{id}/prompt-enhancement/preview`.
abstract interface class PromptEnhancementRepository {
  Future<PromptEnhancementResult> preview(
    String workspaceId,
    PromptEnhancementRequest request,
  );
}

final class PromptEnhancementApiRepository
    implements PromptEnhancementRepository {
  const PromptEnhancementApiRepository(this.api);

  final ApiClient api;

  @override
  Future<PromptEnhancementResult> preview(
    String workspaceId,
    PromptEnhancementRequest request,
  ) async {
    final response = await api.post(
      'v1/workspaces/$workspaceId/prompt-enhancement/preview',
      body: request.body(),
    );
    return parsePromptEnhancement(
      asJsonMap(response['data']),
      fallbackPrompt: request.prompt,
      fallbackModel: request.targetModel,
    );
  }
}

/// Parses a preview response.
///
/// Split from the request so the wire format is testable without a signed-in
/// Firebase user, and type-checked rather than cast: a malformed payload
/// degrades to the text the person already had, which is always a safe answer
/// here, instead of throwing where they expected a rewrite.
PromptEnhancementResult parsePromptEnhancement(
  JsonMap response, {
  required String fallbackPrompt,
  required String fallbackModel,
}) {
  final metadata = asJsonMap(response['promptEnhancement']);
  final prompt = response['prompt'];
  return PromptEnhancementResult(
    prompt: prompt is String && prompt.trim().isNotEmpty
        ? prompt
        : fallbackPrompt,
    status: metadata['status'] as String? ?? 'fallback',
    bible: metadata['bible'] as String? ?? '',
    modality: metadata['modality'] as String? ?? '',
    modelSpecific: metadata['modelSpecific'] as bool? ?? true,
    targetModel: metadata['targetModel'] as String? ?? fallbackModel,
    fallbackReason: metadata['fallbackReason'] as String?,
  );
}

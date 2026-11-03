import 'package:ii_os/repositories/prompt_enhancement_repository.dart';

/// Stands in for the rewriter at the repository seam.
///
/// Records what it was asked so a test can assert the request carried the right
/// field, model, and length budget -- getting any of those wrong is how a
/// narration script ends up rewritten under an image guide, and the request is
/// the only place the client can get it wrong.
final class StubPromptEnhancements implements PromptEnhancementRepository {
  StubPromptEnhancements({this.result, this.failWith});

  /// What to return, or null to echo the prompt back unchanged.
  final PromptEnhancementResult? result;
  final Object? failWith;

  final List<PromptEnhancementRequest> requests = [];

  PromptEnhancementRequest get lastRequest => requests.last;

  @override
  Future<PromptEnhancementResult> preview(
    String workspaceId,
    PromptEnhancementRequest request,
  ) async {
    requests.add(request);
    if (failWith != null) throw failWith!;
    return result ??
        PromptEnhancementResult(
          prompt: 'Rewritten: ${request.prompt}',
          status: 'enhanced',
          bible: 'z-image',
          modality: 'image',
          modelSpecific: true,
          targetModel: request.targetModel,
        );
  }
}

/// A result that leaves the text alone, as a fallback or a disabled workspace
/// does.
PromptEnhancementResult unchangedResult({
  String status = 'fallback',
  String? fallbackReason = 'provider_unavailable',
  String prompt = 'the original',
  String targetModel = 'Z-Image Turbo',
}) => PromptEnhancementResult(
  prompt: prompt,
  status: status,
  bible: 'z-image',
  modality: 'image',
  modelSpecific: true,
  targetModel: targetModel,
  fallbackReason: fallbackReason,
);

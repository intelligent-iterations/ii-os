part of 'video_generation_view_model.dart';

/// How the video surface asks for a rewrite of its shot direction.
///
/// A part rather than lines in the main file: the ViewModel is already at
/// its size guideline, and this is one coherent concern that reads better
/// with its own header than buried among source-asset plumbing.
extension VideoGenerationPromptEnhancement on VideoGenerationViewModel {
  /// How many images the target request will carry.
  ///
  /// The guide writes an image-to-video prompt differently from a text-to-video
  /// one -- it has a first frame to move away from rather than a scene to invent
  /// -- so the count travels with the request.
  int get attachedImageCountForEnhancement => isMiniMaxH3
      ? h3References
            .where((item) => item.kind == MiniMaxH3ReferenceKind.image)
            .length
      : (sourceAssetId == null ? 0 : 1);

  /// The rewrite affordance for the shot direction.
  PromptEnhanceBinding? get promptBinding => isSeedVr2
      ? null
      : enhanceBindingFor(
          field: 'prompt',
          modality: 'video',
          workflowId: selectedTemplate?.workflowId,
          targetModel: selectedTemplate?.model,
          maxLength: selectedTemplate?.inputs['prompt']?.maxLength ?? 7000,
          attachedImageCount: attachedImageCountForEnhancement,
        );
}

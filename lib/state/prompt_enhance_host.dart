import '../models/prompt_guide_source.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../widgets/prompt_enhance_bar.dart';
import 'prompt_enhance_copy.dart';
import 'prompt_enhancement_fields.dart';

/// Builds a field's [PromptEnhanceBinding] for a surface that rebuilds with
/// `setState` rather than through a ViewModel.
///
/// Without this, every such screen repeats the same forty lines -- a rewrite
/// call, an undo that has to remember to rebuild, and a tooltip -- which is how
/// four surfaces end up offering the affordance four subtly different ways.
/// The pages that have a ViewModel get the same behaviour from
/// `PromptEnhancementSupport`.
final class PromptEnhanceHost {
  const PromptEnhanceHost({required this.fields, required this.onChanged});

  final PromptEnhancementFields fields;

  /// Called whenever the rewrite state moves, so the surface can rebuild.
  final void Function() onChanged;

  /// The binding for one field of the workflow currently selected.
  ///
  /// The workflow is passed per call rather than held, because on most of
  /// these surfaces it changes while the page is open.
  /// [field] is the workflow input the text is destined for, and the server
  /// validates it. [stateKey] is where this surface keeps the rewrite state,
  /// and defaults to [field].
  ///
  /// They are separate because a storyboard has many panels whose text all goes
  /// to the same input: one key per panel keeps each panel's undo its own,
  /// while the request still names the input the API knows about.
  PromptEnhanceBinding binding({
    required String field,
    required String workflowId,
    required String targetModel,
    required int maxLength,
    String? stateKey,
    String? modality,
    int attachedImageCount = 0,
    bool storyboardPanel = false,
  }) => _binding(
    key: stateKey ?? field,
    field: field,
    workflowId: workflowId,
    targetModel: targetModel,
    maxLength: maxLength,
    modality: modality,
    attachedImageCount: attachedImageCount,
    storyboardPanel: storyboardPanel,
  );

  PromptEnhanceBinding _binding({
    required String key,
    required String field,
    required String workflowId,
    required String targetModel,
    required int maxLength,
    String? modality,
    int attachedImageCount = 0,
    bool storyboardPanel = false,
  }) => PromptEnhanceBinding(
    outcome: fields.outcome(key),
    message: fields.message(key),
    canUndo: fields.canUndo(key),
    tooltip: promptEnhanceTooltip(targetModel),
    guideSource: officialPromptGuideSourceFor(
      workflowId: workflowId,
      targetModel: targetModel,
      modality: modality,
    ),
    onEnhance: (text) => fields.enhance(
      stateKey: key,
      PromptEnhancementRequest(
        prompt: text,
        workflowId: workflowId,
        targetModel: targetModel,
        field: field,
        modality: modality,
        maxLength: maxLength,
        attachedImageCount: attachedImageCount,
        storyboardPanel: storyboardPanel,
      ),
      onChanged: onChanged,
    ),
    onUndo: () {
      final original = fields.undo(key);
      if (original != null) onChanged();
      return original;
    },
  );
}

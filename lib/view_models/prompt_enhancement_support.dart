import 'package:stacked/stacked.dart';

import '../repositories/prompt_enhancement_repository.dart';
import '../state/prompt_enhance_host.dart';
import '../state/prompt_enhancement_fields.dart';
import '../widgets/prompt_enhance_bar.dart';

/// Rewrite state for a page that has a ViewModel.
///
/// A thin lift of [PromptEnhancementFields] into `BaseViewModel`, so a surface
/// that predates the ViewModel migration and one that does not offer the same
/// affordance from the same state machine.
mixin PromptEnhancementSupport on BaseViewModel {
  PromptEnhancementRepository get promptEnhancements;

  String get workspaceId;

  late final PromptEnhancementFields promptEnhancementFields =
      PromptEnhancementFields(
        repository: promptEnhancements,
        workspaceId: workspaceId,
      );

  late final PromptEnhanceHost promptEnhanceHost = PromptEnhanceHost(
    fields: promptEnhancementFields,
    onChanged: notifyListeners,
  );

  /// True while any field still holds a rewrite the person kept.
  ///
  /// Dispatch enhances the prompt again on its way out, which would rewrite
  /// text this person has already reviewed and accepted. Submitting with this
  /// set tells the server to leave it alone.
  bool get keptEnhancedText => keptEnhancedTextFor('prompt');

  /// Whether this particular workflow field already holds a reviewed rewrite.
  bool keptEnhancedTextFor(String field) =>
      promptEnhancementFields.keptEnhancedTextFor(field);

  /// The rewrite affordance for one field of the given workflow.
  ///
  /// Returns null before a workflow is selected: there is no model to write
  /// for yet, so there is nothing honest the button could promise.
  PromptEnhanceBinding? enhanceBindingFor({
    required String field,
    required String? workflowId,
    required String? targetModel,
    required int maxLength,
    String? modality,
    int attachedImageCount = 0,
  }) {
    if (workflowId == null || targetModel == null) return null;
    return promptEnhanceHost.binding(
      field: field,
      workflowId: workflowId,
      targetModel: targetModel,
      modality: modality,
      maxLength: maxLength,
      attachedImageCount: attachedImageCount,
    );
  }

  /// Forgets the rewrite history, so a submitted form starts clean.
  void resetEnhancements() => promptEnhancementFields.reset();
}

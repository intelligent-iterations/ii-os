part of 'video_generation_view_model.dart';

/// Continuation-only options.
///
/// A continuation is the one mode that reaches a length the source does not
/// already cover, so it is the only one that has to say *how* it gets there.
extension MiniMaxH3Continuation on VideoGenerationViewModel {
  /// Whether the workflow this template dispatches can take a method at all.
  ///
  /// Older catalog entries do not declare it, and those runs still extend --
  /// they just take the default rather than a choice.
  bool get supportsH3ExtensionMethod =>
      supportsH3ReferenceInputs &&
      selectedTemplate!.inputs.containsKey(minimaxH3ExtensionMethodInput);

  void setH3ExtensionMethod(MiniMaxH3ExtensionMethod method) {
    if (h3Mode != MiniMaxH3GenerationMode.videoContinue ||
        h3ExtensionMethod == method) {
      return;
    }
    h3ExtensionMethod = method;
    submittedJob = null;
    setError(null);
    notifyListeners();
  }
}

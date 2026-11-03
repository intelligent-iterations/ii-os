/// Returns the model author's current prompting guidance when ii-os knows the
/// exact image-model family in use.
///
/// An unknown model deliberately gets no link. Calling an ii-os-authored
/// fallback "official" would make its provenance less clear, not more.
Uri? officialPromptGuideSourceFor({
  required String workflowId,
  required String targetModel,
  String? modality,
}) {
  final signal = '$workflowId $targetModel'.toLowerCase();
  final editing = switch (modality?.toLowerCase()) {
    'image_edit' || 'inpaint' => true,
    _ =>
      workflowId.startsWith('image-edit') ||
          workflowId.startsWith('image-inpaint'),
  };

  if (signal.contains('flux')) {
    return Uri.parse(
      editing
          ? 'https://docs.bfl.ml/guides/prompting_editing_overview'
          : 'https://docs.bfl.ml/guides/prompting_unified_building',
    );
  }
  if (signal.contains('qwen')) {
    return Uri.parse(
      editing
          ? 'https://qwen.ai/blog?id=qwen-image-edit-2511'
          : 'https://github.com/QwenLM/Qwen-Image/blob/main/src/examples/'
                'tools/prompt_utils_2512.py',
    );
  }
  if (signal.contains('z-image')) {
    return Uri.parse('https://tongyi-mai.github.io/Z-Image-blog/');
  }
  return null;
}

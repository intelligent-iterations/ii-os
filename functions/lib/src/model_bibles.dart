import 'creative_surface.dart';
import 'prompt_guide_catalog.dart';

export 'model_bible_inpainting.dart' show inpaintingModelBible;
export 'prompt_guide_catalog.dart'
    show
        PromptGuideDefinition,
        PromptGuideLibrary,
        promptGuideCatalog,
        promptGuideMaxLength,
        promptGuidesById;

const String deepSeekPromptEnhancementModel = 'deepseek-v4-flash';

/// The generator families ii-os ships a specific guide for.
enum ModelFamily {
  zImage('z-image'),
  flux('flux'),
  qwen('qwen'),
  ltx('ltx'),
  minimaxH3('minimax-h3'),
  aceStep('ace-step'),
  chatterbox('chatterbox'),
  unknown('unknown');

  const ModelFamily(this.id);

  final String id;
}

final class ModelBibleSelection {
  const ModelBibleSelection({
    required this.id,
    required this.guide,
    required this.modality,
    this.customized = false,
  });

  /// Names the resolution, not the document: `qwen-inpaint` is the Qwen editing
  /// guide followed by the inpainting contract, and neither of those is called
  /// `qwen-inpaint`.
  final String id;
  final String guide;
  final CreativeModality modality;

  /// True when any guide in this selection is a customer's edit rather than the
  /// text ii-os ships.
  ///
  /// Recorded on the run: when a generation comes out strangely, the first
  /// question is whether it was steered by a guide somebody changed, and the
  /// job metadata is where that has to be answerable.
  final bool customized;

  /// False when the guide applied was a modality fallback, not one written for
  /// this model.
  bool get isModelSpecific => !id.startsWith('generic-');
}

/// Identifies the generator family behind a model name.
ModelFamily modelFamilyFor(String model, {String workflowId = ''}) {
  final signal = '$model $workflowId'.toLowerCase().replaceAll('_', '-').trim();
  if (signal.contains('minimax-h3') || signal.contains('minimax h3')) {
    return ModelFamily.minimaxH3;
  }
  if (signal.contains('ltx')) return ModelFamily.ltx;
  if (signal.contains('ace-step') ||
      signal.contains('acestep') ||
      signal.contains('song-create')) {
    return ModelFamily.aceStep;
  }
  if (signal.contains('chatterbox') ||
      signal.contains('narration') ||
      signal.contains('tts')) {
    return ModelFamily.chatterbox;
  }
  if (signal.contains('qwen')) return ModelFamily.qwen;
  if (signal.contains('flux')) return ModelFamily.flux;
  if (signal.contains('z-image') || signal.contains('z image')) {
    return ModelFamily.zImage;
  }
  return ModelFamily.unknown;
}

/// Resolves the guide for one creative field on one model.
///
/// Modality is decided first and family second. Getting that order wrong is
/// what let a text-to-speech workflow inherit an image guide: `chatterbox` was
/// simply not a name any branch tested for, so the chain fell through to the
/// Z-Image default and rewrote a narration script as a photograph.
///
/// [library] supplies the text. It carries whatever an administrator has
/// edited, so every branch below names a guide by id and never reaches for a
/// constant directly.
ModelBibleSelection modelBibleSelectionFor(
  String model, {
  String workflowId = '',
  String field = 'prompt',
  CreativeModality? modality,
  int attachedImageCount = 0,
  PromptGuideLibrary library = PromptGuideLibrary.defaults,
}) {
  final resolved =
      modality ??
      creativeModalityFor(
        field: field,
        workflowId: workflowId,
        model: model,
        attachedImageCount: attachedImageCount,
      );
  final family = modelFamilyFor(model, workflowId: workflowId);
  return switch (resolved) {
    CreativeModality.speech => _speech(family, library),
    CreativeModality.lyrics => _lyrics(family, library),
    CreativeModality.music => _music(family, library),
    CreativeModality.video => _video(family, library),
    CreativeModality.inpaint => _inpaint(family, library),
    CreativeModality.imageEdit => _imageEdit(family, library),
    CreativeModality.image => _image(family, library),
  };
}

String modelBibleFor(String model, {String workflowId = ''}) =>
    modelBibleSelectionFor(model, workflowId: workflowId).guide;

ModelBibleSelection _speech(ModelFamily family, PromptGuideLibrary library) =>
    _one(
      family == ModelFamily.chatterbox ? 'chatterbox-speech' : 'generic-speech',
      CreativeModality.speech,
      library,
    );

ModelBibleSelection _lyrics(ModelFamily family, PromptGuideLibrary library) =>
    _one(
      family == ModelFamily.aceStep ? 'ace-step-lyrics' : 'generic-lyrics',
      CreativeModality.lyrics,
      library,
    );

ModelBibleSelection _music(ModelFamily family, PromptGuideLibrary library) =>
    _one(
      family == ModelFamily.aceStep ? 'ace-step' : 'generic-music',
      CreativeModality.music,
      library,
    );

ModelBibleSelection _video(ModelFamily family, PromptGuideLibrary library) =>
    _one(
      switch (family) {
        ModelFamily.minimaxH3 => 'minimax-h3-video',
        ModelFamily.ltx => 'ltx-video',
        _ => 'generic-video',
      },
      CreativeModality.video,
      library,
    );

ModelBibleSelection _inpaint(ModelFamily family, PromptGuideLibrary library) =>
    switch (family) {
      ModelFamily.qwen => _composed('qwen-inpaint', 'qwen-edit', library),
      ModelFamily.flux => _composed('flux-inpaint', 'flux', library),
      ModelFamily.zImage => _composed('z-image-inpaint', 'z-image', library),
      _ => _composed('generic-inpaint', 'generic-image-edit', library),
    };

ModelBibleSelection _imageEdit(
  ModelFamily family,
  PromptGuideLibrary library,
) => switch (family) {
  ModelFamily.qwen => _one('qwen-edit', CreativeModality.imageEdit, library),
  ModelFamily.flux => _composed(
    'flux-edit',
    'flux',
    library,
    addendumId: 'generic-image-edit',
    modality: CreativeModality.imageEdit,
  ),
  ModelFamily.zImage => _composed(
    'z-image-edit',
    'z-image',
    library,
    addendumId: 'generic-image-edit',
    modality: CreativeModality.imageEdit,
  ),
  _ => _one('generic-image-edit', CreativeModality.imageEdit, library),
};

ModelBibleSelection _image(ModelFamily family, PromptGuideLibrary library) =>
    _one(
      switch (family) {
        ModelFamily.zImage => 'z-image',
        ModelFamily.flux => 'flux',
        ModelFamily.qwen => 'qwen-image',
        _ => 'generic-image',
      },
      CreativeModality.image,
      library,
    );

ModelBibleSelection _one(
  String guideId,
  CreativeModality modality,
  PromptGuideLibrary library,
) => ModelBibleSelection(
  id: guideId,
  guide: library.body(guideId),
  modality: modality,
  customized: library.isCustomized(guideId),
);

/// Layers a modality contract on top of a family's own guide.
///
/// Inpainting and editing do not replace how a model reads a prompt; they
/// change what the prompt is about. Composing keeps both rule sets in front of
/// the rewriter instead of making it choose between them.
ModelBibleSelection _composed(
  String id,
  String familyGuideId,
  PromptGuideLibrary library, {
  String addendumId = 'inpainting',
  CreativeModality modality = CreativeModality.inpaint,
}) => ModelBibleSelection(
  id: id,
  guide:
      '${library.body(familyGuideId).trim()}\n\n'
      '${library.body(addendumId).trim()}',
  modality: modality,
  customized:
      library.isCustomized(familyGuideId) || library.isCustomized(addendumId),
);

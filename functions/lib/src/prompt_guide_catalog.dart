import 'creative_surface.dart';
import 'model_bible_acestep.dart';
import 'model_bible_chatterbox.dart';
import 'model_bible_flux.dart';
import 'model_bible_generic.dart';
import 'model_bible_inpainting.dart';
import 'model_bible_ltx.dart';
import 'model_bible_lyrics.dart';
import 'model_bible_minimax_h3.dart';
import 'model_bible_qwen.dart';
import 'model_bible_qwen_image.dart';
import 'model_bible_z_image.dart';

/// One guide an administrator can edit.
///
/// The editable units are the *source* texts, not the composed results. A Qwen
/// inpaint prompt is answered by the Qwen editing guide followed by the
/// inpainting contract; exposing that combination as its own editable document
/// would mean the same inpainting rules were maintained in three places and
/// drifted apart in two of them.
final class PromptGuideDefinition {
  const PromptGuideDefinition({
    required this.id,
    required this.label,
    required this.summary,
    required this.modality,
    required this.body,
    this.authoredByIiOs = false,
  });

  final String id;

  /// What a person sees in the list. Names the model or the job, never the
  /// constant behind it.
  final String label;

  /// One sentence on when this guide is the one that applies.
  final String summary;
  final CreativeModality modality;

  /// The text ii-os ships, and what a reset returns to.
  final String body;

  /// True when ii-os wrote this guide rather than transcribing the vendor's.
  ///
  /// Worth surfacing: a vendor's own documentation is the authority on how its
  /// model reads a prompt, and ii-os's own prose is a considered guess. Someone
  /// deciding whether to edit should be able to tell which one they are
  /// looking at.
  final bool authoredByIiOs;
}

/// Every guide the enhancer can apply, in the order the settings screen lists
/// them: the models a workspace generates with first, then the fallbacks that
/// answer a model nobody has written rules for.
const List<PromptGuideDefinition> promptGuideCatalog = [
  PromptGuideDefinition(
    id: 'z-image',
    label: 'Z-Image Turbo',
    summary: 'Text-to-image generation on Z-Image Turbo.',
    modality: CreativeModality.image,
    body: zImageTurboModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'flux',
    label: 'FLUX.2',
    summary: 'Text-to-image generation on any FLUX model.',
    modality: CreativeModality.image,
    body: fluxImageModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'qwen-image',
    label: 'Qwen Image',
    summary: 'Text-to-image generation on Qwen Image.',
    modality: CreativeModality.image,
    body: qwenImageModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'qwen-edit',
    label: 'Qwen Image Edit',
    summary: 'Editing an existing image with Qwen.',
    modality: CreativeModality.imageEdit,
    body: qwenImageEditModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'inpainting',
    label: 'Inpainting',
    summary:
        'Added to the model\'s own guide whenever a prompt describes a masked '
        'region rather than a whole image.',
    modality: CreativeModality.inpaint,
    body: inpaintingModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'ltx-video',
    label: 'LTX',
    summary: 'Image-to-video and text-to-video on LTX.',
    modality: CreativeModality.video,
    body: ltxVideoModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'minimax-h3-video',
    label: 'MiniMax H3',
    summary: 'Audiovisual generation, editing, and continuation on H3.',
    modality: CreativeModality.video,
    body: minimaxH3VideoModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'ace-step',
    label: 'ACE-Step song description',
    summary: 'The caption describing a song ACE-Step will compose.',
    modality: CreativeModality.music,
    body: aceStepMusicModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'ace-step-lyrics',
    label: 'ACE-Step lyrics',
    summary: 'Lyrics ACE-Step sings as written.',
    modality: CreativeModality.lyrics,
    body: aceStepLyricsModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'chatterbox-speech',
    label: 'Chatterbox narration',
    summary: 'A script Chatterbox reads aloud, word for word.',
    modality: CreativeModality.speech,
    body: chatterboxNarrationModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'generic-image',
    label: 'Any other image model',
    summary: 'Used when no guide is written for the image model in use.',
    modality: CreativeModality.image,
    body: genericImageModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'generic-image-edit',
    label: 'Any other image editor',
    summary: 'Used when no guide is written for the editing model in use.',
    modality: CreativeModality.imageEdit,
    body: genericImageEditModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'generic-video',
    label: 'Any other video model',
    summary: 'Used when no guide is written for the video model in use.',
    modality: CreativeModality.video,
    body: genericVideoModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'generic-music',
    label: 'Any other music model',
    summary: 'Used when no guide is written for the music model in use.',
    modality: CreativeModality.music,
    body: genericMusicModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'generic-lyrics',
    label: 'Any other lyrics field',
    summary: 'Used when no guide is written for the singing model in use.',
    modality: CreativeModality.lyrics,
    body: genericLyricsModelBible,
    authoredByIiOs: true,
  ),
  PromptGuideDefinition(
    id: 'generic-speech',
    label: 'Any other narration model',
    summary: 'Used when no guide is written for the voice model in use.',
    modality: CreativeModality.speech,
    body: genericSpeechModelBible,
    authoredByIiOs: true,
  ),
];

/// The longest a guide may be.
///
/// Generous, because a detailed model guide runs to several thousand
/// characters, and bounded because the whole guide is sent as the system
/// message on every rewrite.
const int promptGuideMaxLength = 40000;

final Map<String, PromptGuideDefinition> promptGuidesById = {
  for (final guide in promptGuideCatalog) guide.id: guide,
};

/// Resolves guide text, preferring an administrator's edit over the default.
///
/// Constructed per request from whatever overrides were loaded, and passed down
/// so nothing below it has to know where a guide came from -- the resolver
/// composes the same way whether the text is ii-os's or the customer's.
final class PromptGuideLibrary {
  const PromptGuideLibrary([this.overrides = const {}]);

  /// Guide id to replacement text, already merged across scopes.
  final Map<String, String> overrides;

  static const PromptGuideLibrary defaults = PromptGuideLibrary();

  bool get isEmpty => overrides.isEmpty;

  /// True when this guide is the customer's text rather than the one ii-os
  /// ships.
  bool isCustomized(String id) => _override(id) != null;

  /// The text to send, falling back to the shipped default.
  ///
  /// An unknown id returns empty rather than throwing: guide ids travel in
  /// stored documents, and one left behind by a removed model must not take
  /// down every generation in the workspace.
  String body(String id) => _override(id) ?? promptGuidesById[id]?.body ?? '';

  String? _override(String id) {
    if (!promptGuidesById.containsKey(id)) return null;
    final value = overrides[id]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/widgets.dart' show IconData;

import 'models.dart';
import 'image_workflow_capabilities.dart';

/// What one generation model is for, in words the person choosing it can act
/// on.
///
/// The catalog names checkpoints -- `image-create-qwen-2512`, `FLUX.2 Klein 4B`.
/// Those names are correct and tell a first-time user nothing: they say which
/// weights will run, not which one gets them the picture they want. This is the
/// other half, and it lives next to the model list rather than in a doc nobody
/// opens mid-task.
final class CreativeModelGuide {
  const CreativeModelGuide({
    required this.summary,
    required this.icon,
    this.facts = const [],
  });

  /// One sentence: what this model is good at, and therefore when to pick it.
  final String summary;

  /// The glyph that carries the model's character in a dense list.
  final IconData icon;

  /// Short facts that settle a close call -- how fast, what it accepts.
  final List<String> facts;
}

/// The guide for [template], falling back to its own model name.
///
/// A workspace catalog can offer a workflow this build has never heard of. That
/// must degrade to a card with a plain sentence, never to a blank one -- an
/// option with no reason beside it is worse than a dropdown, because it takes
/// more room to say the same nothing.
CreativeModelGuide creativeModelGuide(WorkflowTemplateModel template) =>
    _guides[template.workflowId] ?? _fallback(template);

List<String> creativeModelFacts(WorkflowTemplateModel template) {
  final facts = [...creativeModelGuide(template).facts];
  final images = imageCapabilities(template).maximumReferenceImages;
  if (images > 0) {
    facts.add(images == 1 ? '1 image required' : 'Up to $images images');
  }
  return facts;
}

const _guides = <String, CreativeModelGuide>{
  'image-create': CreativeModelGuide(
    summary: 'Fast, clean images from a plain description.',
    icon: LucideIcons.zap,
    facts: ['Fastest', 'Good default'],
  ),
  'image-create-flux2-klein': CreativeModelGuide(
    summary: 'Holds detail where it shows: faces, hands, and lettering.',
    icon: LucideIcons.gem,
    facts: ['Most detail'],
  ),
  'image-create-qwen-2512': CreativeModelGuide(
    summary: 'Follows a long, specific description closely.',
    icon: LucideIcons.listChecks,
    facts: ['Most literal', 'Best for long prompts'],
  ),
  'image-create-reference-flux2-klein': CreativeModelGuide(
    summary: 'Builds a detailed image from a main picture and optional guide.',
    icon: LucideIcons.images,
    facts: ['Most detail'],
  ),
  'image-create-reference-qwen-2511': CreativeModelGuide(
    summary: 'Combines several pictures by following a specific instruction.',
    icon: LucideIcons.images,
    facts: ['Most literal'],
  ),
  'image-edit': CreativeModelGuide(
    summary: 'Quick changes that keep the original composition.',
    icon: LucideIcons.zap,
    facts: ['Fastest'],
  ),
  'image-edit-flux2-klein': CreativeModelGuide(
    summary: 'Changes that have to survive a close look.',
    icon: LucideIcons.gem,
    facts: ['Most detail'],
  ),
  'image-edit-qwen-2511': CreativeModelGuide(
    summary: 'Changes guided by other pictures as well as your instruction.',
    icon: LucideIcons.images,
    facts: ['Most literal'],
  ),
  'image-inpaint': CreativeModelGuide(
    summary: 'Repaints the area you mark and leaves the rest untouched.',
    icon: LucideIcons.brush,
    facts: ['Fastest'],
  ),
  'image-inpaint-qwen': CreativeModelGuide(
    summary: 'Repaints marked areas, and can follow several at once.',
    icon: LucideIcons.brush,
    facts: ['Several areas at once'],
  ),
  'image-to-video': CreativeModelGuide(
    summary: 'Puts a still picture you already have into motion.',
    icon: LucideIcons.play,
    facts: ['Silent', 'Up to 20 seconds'],
  ),
  'text-to-video-minimax-h3': CreativeModelGuide(
    summary: 'Shoots a scene from a description, with its own sound.',
    icon: LucideIcons.clapperboard,
    // The licence note stays on the card rather than in a doc: what the
    // finished video may be used for is decided by the model's community
    // license, and the moment to check it is before spending GPU time
    // producing one.
    facts: [
      'With audio',
      'Up to 15 seconds',
      'Check license terms and territory',
    ],
  ),
  'song-create-acestep-xl-sft': CreativeModelGuide(
    summary: 'Writes and performs a song from a description of it.',
    icon: LucideIcons.music,
    facts: ['Vocals or instrumental'],
  ),
  'narration-create-chatterbox-tts': CreativeModelGuide(
    summary: 'Reads a script aloud in a voice you choose.',
    icon: LucideIcons.mic,
    facts: ['Can match a voice you supply'],
  ),
};

CreativeModelGuide _fallback(WorkflowTemplateModel template) {
  final name = template.model.isNotEmpty
      ? template.model
      : template.displayName;
  return CreativeModelGuide(
    summary: 'Runs $name, as configured in this workspace.',
    icon: LucideIcons.box,
  );
}

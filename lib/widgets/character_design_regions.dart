import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum CharacterDesignKind { head, body, combined }

final class CharacterDesignRegion {
  const CharacterDesignRegion({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.questionKeys,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final List<String> questionKeys;
}

const headDesignRegions = <CharacterDesignRegion>[
  CharacterDesignRegion(
    id: 'face',
    label: 'Face shape',
    description: 'Shape the skin, cheeks, jaw and underlying face structure.',
    icon: LucideIcons.scanFace,
    questionKeys: [
      'skinTone',
      'faceShape',
      'cheekbonesAndCheeks',
      'jawAndChin',
    ],
  ),
  CharacterDesignRegion(
    id: 'eyes',
    label: 'Eyes & brows',
    description: 'Describe the eyes, eyelids, gaze and eyebrow structure.',
    icon: LucideIcons.eye,
    questionKeys: ['eyes', 'eyebrows'],
  ),
  CharacterDesignRegion(
    id: 'nose',
    label: 'Nose',
    description: 'Control the bridge, profile, tip and nostrils.',
    icon: LucideIcons.focus,
    questionKeys: ['nose'],
  ),
  CharacterDesignRegion(
    id: 'mouth',
    label: 'Mouth',
    description: 'Define the lips and the expression held across every view.',
    icon: LucideIcons.smile,
    questionKeys: ['lips', 'expression'],
  ),
  CharacterDesignRegion(
    id: 'ears',
    label: 'Ears & jewelry',
    description: 'Describe the ears and accessories attached around the face.',
    icon: LucideIcons.ear,
    questionKeys: ['ears', 'accessories'],
  ),
  CharacterDesignRegion(
    id: 'hair',
    label: 'Hair',
    description: 'Set the texture, style and hairline from every angle.',
    icon: LucideIcons.scissors,
    questionKeys: ['hairTypeAndTexture', 'hairStyle', 'hairline'],
  ),
  CharacterDesignRegion(
    id: 'details',
    label: 'Identity marks',
    description: 'Lock in asymmetries, marks and recognizable features.',
    icon: LucideIcons.sparkles,
    questionKeys: [
      'physicalQuirks',
      'identifiableMarks',
      'recognizableFeatures',
    ],
  ),
  CharacterDesignRegion(
    id: 'headClothing',
    label: 'Visible clothing',
    description: 'Control what appears around the neck and shoulders.',
    icon: LucideIcons.shirt,
    questionKeys: ['clothing', 'visibleClothing'],
  ),
];

const bodyDesignRegions = <CharacterDesignRegion>[
  CharacterDesignRegion(
    id: 'silhouette',
    label: 'Silhouette',
    description: 'Establish height, proportions, posture and signature shape.',
    icon: LucideIcons.personStanding,
    questionKeys: [
      'heightBuildSilhouetteProportions',
      'postureAsymmetries',
      'identifyingBodilyDetails',
    ],
  ),
  CharacterDesignRegion(
    id: 'upperBody',
    label: 'Upper body',
    description: 'Shape the neck, shoulders, torso, chest and abdomen.',
    icon: LucideIcons.accessibility,
    questionKeys: ['neckShouldersUpperTorso', 'chestWaistAbdomen'],
  ),
  CharacterDesignRegion(
    id: 'armsHands',
    label: 'Arms & hands',
    description: 'Set limb length, musculature, hands and fingers.',
    icon: LucideIcons.hand,
    questionKeys: ['armsHands'],
  ),
  CharacterDesignRegion(
    id: 'hips',
    label: 'Hips & pelvis',
    description: 'Control the pelvis, hip width and seat.',
    icon: LucideIcons.move3d,
    questionKeys: ['hipsPelvisSeat'],
  ),
  CharacterDesignRegion(
    id: 'legsFeet',
    label: 'Legs & feet',
    description: 'Describe thighs, knees, calves, ankles, feet and toes.',
    icon: LucideIcons.footprints,
    questionKeys: ['legsFeet'],
  ),
  CharacterDesignRegion(
    id: 'outfit',
    label: 'Outfit concept',
    description: 'Set the setting, silhouette, layers, materials and palette.',
    icon: LucideIcons.palette,
    questionKeys: [
      'outfitConceptSettingSilhouette',
      'completeGarmentsLayering',
      'materialsColorsDecorativeDetails',
    ],
  ),
  CharacterDesignRegion(
    id: 'upperClothing',
    label: 'Upper clothing',
    description: 'Design upper garments, outerwear and headwear together.',
    icon: LucideIcons.shirt,
    questionKeys: [
      'upperGarment',
      'outerwearDrapedGarment',
      'headwearHairstyleInteraction',
    ],
  ),
  CharacterDesignRegion(
    id: 'lowerClothing',
    label: 'Lower clothing',
    description: 'Design the lower garment, legwear and footwear.',
    icon: LucideIcons.ruler,
    questionKeys: ['lowerGarment', 'legwearFootwear'],
  ),
  CharacterDesignRegion(
    id: 'bodyAccessories',
    label: 'Accessories',
    description: 'Specify accessories, closures and carried objects.',
    icon: LucideIcons.gem,
    questionKeys: ['accessoriesClosuresCarriedObjects'],
  ),
];

const combinedDesignRegions = <CharacterDesignRegion>[
  ...headDesignRegions,
  ...bodyDesignRegions,
];

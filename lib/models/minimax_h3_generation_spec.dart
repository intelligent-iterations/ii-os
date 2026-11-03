import 'dart:convert';
import 'dart:typed_data';

const minimaxH3GenerationModeInput = 'generation_mode';
const minimaxH3PerformanceModeInput = 'performance_mode';
const minimaxH3ReferenceManifestInput = 'reference_manifest';
const minimaxH3EditOperationInput = 'edit_operation';
const minimaxH3IdentityConsentInput = 'identity_replacement_consent';
const minimaxH3ExtensionMethodInput = 'extension_method';

enum MiniMaxH3PerformanceMode {
  quality(
    wireValue: 'quality',
    label: 'Quality',
    description: 'Highest fine-detail fidelity. This is the slower option.',
  ),
  turbo(
    wireValue: 'turbo',
    label: 'Turbo',
    description:
        'Much faster generation with a small possible loss of fine detail.',
  );

  const MiniMaxH3PerformanceMode({
    required this.wireValue,
    required this.label,
    required this.description,
  });

  final String wireValue;
  final String label;
  final String description;
}

enum MiniMaxH3GenerationMode {
  textToVideo(
    wireValue: 'text_to_video',
    label: 'Text to video',
    description: 'Generate a complete audiovisual scene from a prompt.',
  ),
  firstFrame(
    wireValue: 'first_frame_to_video',
    label: 'First frame',
    description: 'Animate one image as the opening frame.',
  ),
  lastFrame(
    wireValue: 'last_frame_to_video',
    label: 'Last frame',
    description: 'Generate toward one image as the final frame.',
  ),
  firstLastFrame(
    wireValue: 'first_last_frame_to_video',
    label: 'First + last',
    description: 'Create a transition between two exact endpoint frames.',
  ),
  referenceToVideo(
    wireValue: 'reference_to_video',
    label: 'References',
    description: 'Guide subjects, style, motion, environment, and audio.',
  ),
  videoEdit(
    wireValue: 'video_edit',
    label: 'Video edit',
    description: 'Transform a source video while preserving its timeline.',
  ),
  videoContinue(
    wireValue: 'video_continue',
    label: 'Continue video',
    description:
        'Continue naturally from a source video\u2019s final moment and sound.',
  );

  const MiniMaxH3GenerationMode({
    required this.wireValue,
    required this.label,
    required this.description,
  });

  final String wireValue;
  final String label;
  final String description;
}

enum MiniMaxH3ReferenceKind {
  image(label: 'Image'),
  video(label: 'Video'),
  audio(label: 'Audio');

  const MiniMaxH3ReferenceKind({required this.label});

  final String label;
}

enum MiniMaxH3ReferenceRole {
  firstFrame(
    wireValue: 'first_frame',
    label: 'First frame',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  lastFrame(
    wireValue: 'last_frame',
    label: 'Last frame',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  subject(
    wireValue: 'subject',
    label: 'Subject / object identity',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  style(
    wireValue: 'style',
    label: 'Visual style',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  environment(
    wireValue: 'environment',
    label: 'Environment',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  poseReference(
    wireValue: 'pose_reference',
    label: 'Action / pose',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  effectReference(
    wireValue: 'effect_reference',
    label: 'Visual effect',
    kind: MiniMaxH3ReferenceKind.image,
  ),
  sourceVideo(
    wireValue: 'source_video',
    label: 'Source video',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  motionReference(
    wireValue: 'motion_reference',
    label: 'Motion reference',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  videoSubject(
    wireValue: 'video_subject',
    label: 'Subject / object identity',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  videoStyle(
    wireValue: 'video_style',
    label: 'Visual style',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  videoEnvironment(
    wireValue: 'video_environment',
    label: 'Environment',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  videoAction(
    wireValue: 'video_action',
    label: 'Action / pose',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  videoEffect(
    wireValue: 'video_effect',
    label: 'Visual effect',
    kind: MiniMaxH3ReferenceKind.video,
  ),
  audioReference(
    wireValue: 'audio_reference',
    label: 'Audio direction',
    kind: MiniMaxH3ReferenceKind.audio,
  ),
  audioReuse(
    wireValue: 'audio_reuse',
    label: 'Reuse audio',
    kind: MiniMaxH3ReferenceKind.audio,
  );

  const MiniMaxH3ReferenceRole({
    required this.wireValue,
    required this.label,
    required this.kind,
  });

  final String wireValue;
  final String label;
  final MiniMaxH3ReferenceKind kind;
}

enum MiniMaxH3EditOperation {
  general(wireValue: 'general_edit', label: 'Directed edit'),
  characterReplacement(
    wireValue: 'character_replacement',
    label: 'Character / face replacement',
  ),
  objectReplacement(
    wireValue: 'object_replacement',
    label: 'Object replacement',
  ),
  motionTransfer(wireValue: 'motion_transfer', label: 'Motion transfer'),
  backgroundReplacement(
    wireValue: 'background_replacement',
    label: 'Background replacement',
  );

  const MiniMaxH3EditOperation({required this.wireValue, required this.label});

  final String wireValue;
  final String label;
}

/// How a continuation reaches its finished length.
///
/// Both anchor the source with `MiniMaxH3AddGuide` rather than describing the
/// continuation in prose, which is what makes the model carry on instead of
/// restarting. They differ in how much they render at once.
enum MiniMaxH3ExtensionMethod {
  singlePass(
    wireValue: 'single_pass',
    label: 'One pass',
    description:
        'Renders the finished video in a single pass with the source '
        'anchored at its opening. No seam, and the soundtrack carries '
        'through. Limited to what one render can hold.',
  ),
  chained(
    wireValue: 'chained',
    label: 'Chained segments',
    description:
        'Renders in segments and joins them in latent space, decoding once '
        'at the end. Keeps the source frames exactly and reaches past a '
        'single render, at the cost of a longer job.',
  );

  const MiniMaxH3ExtensionMethod({
    required this.wireValue,
    required this.label,
    required this.description,
  });

  final String wireValue;
  final String label;
  final String description;
}

final class MiniMaxH3ReferenceDraft {
  const MiniMaxH3ReferenceDraft({
    required this.id,
    required this.filename,
    required this.bytes,
    required this.contentType,
    required this.kind,
    required this.role,
    this.assetId,
  });

  final String id;
  final String filename;
  final Uint8List bytes;
  final String contentType;
  final MiniMaxH3ReferenceKind kind;
  final MiniMaxH3ReferenceRole role;
  final String? assetId;

  factory MiniMaxH3ReferenceDraft.uploaded({
    required String id,
    required String filename,
    required String contentType,
    required MiniMaxH3ReferenceKind kind,
    required MiniMaxH3ReferenceRole role,
    required String assetId,
  }) => MiniMaxH3ReferenceDraft(
    id: id,
    filename: filename,
    bytes: Uint8List(0),
    contentType: contentType,
    kind: kind,
    role: role,
    assetId: assetId,
  );

  MiniMaxH3ReferenceDraft copyWith({
    MiniMaxH3ReferenceRole? role,
    String? assetId,
    Uint8List? bytes,
    bool clearAssetId = false,
  }) => MiniMaxH3ReferenceDraft(
    id: id,
    filename: filename,
    bytes: bytes ?? this.bytes,
    contentType: contentType,
    kind: kind,
    role: role ?? this.role,
    assetId: clearAssetId ? null : assetId ?? this.assetId,
  );
}

abstract final class MiniMaxH3GenerationSpec {
  static const schemaVersion = 1;
  static const minimumDurationSeconds = 4;
  static const maximumDurationSeconds = 15;
  static const maximumReferences = 12;
  static const maximumImages = 9;
  static const maximumVideos = 3;
  static const maximumAudioFiles = 3;
  static const maximumImageBytes = 50 * 1024 * 1024;
  static const maximumVideoBytes = 512 * 1024 * 1024;
  static const maximumAudioBytes = 50 * 1024 * 1024;

  static List<MiniMaxH3ReferenceRole> rolesFor(MiniMaxH3ReferenceKind kind) =>
      MiniMaxH3ReferenceRole.values
          .where((role) => role.kind == kind)
          .toList(growable: false);

  static String encodeManifest({
    required MiniMaxH3GenerationMode mode,
    required List<MiniMaxH3ReferenceDraft> references,
    required MiniMaxH3EditOperation editOperation,
    required bool identityReplacementConsent,
  }) {
    final missingUpload = references.any(
      (reference) => reference.assetId == null || reference.assetId!.isEmpty,
    );
    if (missingUpload) {
      throw StateError('Every MiniMax H3 reference must be uploaded first.');
    }
    return jsonEncode({
      'schema_version': schemaVersion,
      'mode': mode.wireValue,
      'references': [
        for (var index = 0; index < references.length; index++)
          {
            'asset_id': references[index].assetId,
            'kind': references[index].kind.name,
            'role': references[index].role.wireValue,
            'ordinal': index,
          },
      ],
      if (mode == MiniMaxH3GenerationMode.videoEdit)
        'edit_operation': editOperation.wireValue,
      if (mode == MiniMaxH3GenerationMode.videoEdit)
        'identity_replacement_consent': identityReplacementConsent,
    });
  }
}

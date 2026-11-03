import 'dart:convert';

import 'api_error.dart';

const workflowReferenceManifestInput = 'reference_manifest';

/// The input a video-editor export sends: the whole compiled render, naming
/// every file it reads.
const workflowRenderManifestInput = 'render_manifest';

/// A render's filtergraph grows with its timeline. This matches the catalog's
/// own ceiling for a string input, so a render that fits here is a render
/// GitHub will accept; anything larger is refused before it is stored.
const workflowRenderManifestLimit = 60000;

/// How many files one render may read on a runner. The editor's own compiler
/// stops at sixteen; a dispatched render stops earlier so a single export
/// cannot occupy a runner fetching media all day.
const workflowMaxRenderInputs = 12;

final RegExp _renderInputName = RegExp(r'^input-[0-9]{1,2}\.[a-z0-9]{1,10}$');

final class WorkflowSourceReference {
  const WorkflowSourceReference({
    required this.assetId,
    required this.inputField,
    this.kind,
    this.role,
    this.ordinal,
  });

  final String assetId;
  final String inputField;
  final String? kind;
  final String? role;
  final int? ordinal;
}

List<WorkflowSourceReference> workflowSourceReferences(
  Map<String, Object?> inputs,
) {
  final legacy = _legacyReferences(inputs);
  final rawManifest = inputs[workflowReferenceManifestInput];
  final rawRender = inputs[workflowRenderManifestInput];
  if (rawRender != null && rawRender != '') {
    if (legacy.isNotEmpty || (rawManifest != null && rawManifest != '')) {
      throw _invalidRender(
        'A render describes everything it reads, so it cannot be combined '
        'with other reference inputs.',
      );
    }
    return _renderReferences(rawRender);
  }
  if (rawManifest == null || rawManifest == '') return legacy;
  if (legacy.isNotEmpty) {
    throw _invalidManifest(
      'Reference manifests cannot be combined with legacy source inputs.',
    );
  }
  if (rawManifest is! String || rawManifest.length > 30000) {
    throw _invalidManifest('The reference manifest is not bounded JSON.');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(rawManifest);
  } on FormatException {
    throw _invalidManifest('The reference manifest is not valid JSON.');
  }
  final manifest = _map(decoded);
  _requireKeys(manifest, const {
    'schema_version',
    'mode',
    'references',
    'edit_operation',
    'identity_replacement_consent',
  });
  if (manifest['schema_version'] != 1) {
    throw _invalidManifest('The reference manifest version is unsupported.');
  }
  final mode = manifest['mode'];
  if (mode is! String || !_modes.contains(mode)) {
    throw _invalidManifest('The MiniMax H3 generation mode is invalid.');
  }
  final declaredMode = inputs['generation_mode'];
  if (declaredMode != null && declaredMode != mode) {
    throw _invalidManifest('The reference manifest mode does not match.');
  }

  final rawReferences = manifest['references'];
  if (rawReferences is! List<Object?> || rawReferences.length > 12) {
    throw _invalidManifest('The reference manifest exceeds 12 files.');
  }
  final references = <WorkflowSourceReference>[];
  final assetIds = <String>{};
  for (var index = 0; index < rawReferences.length; index++) {
    final value = _map(rawReferences[index]);
    _requireKeys(value, const {'asset_id', 'kind', 'role', 'ordinal'});
    final assetId = value['asset_id'];
    final kind = value['kind'];
    final role = value['role'];
    final ordinal = value['ordinal'];
    if (assetId is! String ||
        !_assetIdPattern.hasMatch(assetId) ||
        !assetIds.add(assetId) ||
        kind is! String ||
        role is! String ||
        _roles[role] != kind ||
        ordinal != index) {
      throw _invalidManifest('A reference manifest entry is invalid.');
    }
    references.add(
      WorkflowSourceReference(
        assetId: assetId,
        inputField: workflowReferenceManifestInput,
        kind: kind,
        role: role,
        ordinal: index,
      ),
    );
  }
  _validateCounts(references);
  _validateMode(manifest, inputs, mode, references);
  return references;
}

void validateWorkflowSourceReferences(Map<String, Object?> inputs) {
  workflowSourceReferences(inputs);
}

/// The media a compiled render reads, in the order its arguments name them.
///
/// The names matter as much as the ids: the render's arguments refer to
/// `input-0.mp4`, so each contract carries the name its bytes have to be
/// written under before FFmpeg is run.
List<WorkflowSourceReference> _renderReferences(Object? raw) {
  if (raw is! String || raw.length > workflowRenderManifestLimit) {
    throw _invalidRender('The render is not bounded JSON.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw _invalidRender('The render is not valid JSON.');
  }
  final manifest = decoded;
  if (manifest is! Map || manifest['version'] != 1) {
    throw _invalidRender('The render was described by another version.');
  }
  final entries = manifest['inputs'];
  if (entries is! List || entries.isEmpty) {
    throw _invalidRender('A render has to read at least one file.');
  }
  if (entries.length > workflowMaxRenderInputs) {
    throw _invalidRender(
      'A render may read at most $workflowMaxRenderInputs files.',
    );
  }
  final references = <WorkflowSourceReference>[];
  final names = <String>{};
  for (var ordinal = 0; ordinal < entries.length; ordinal++) {
    final entry = entries[ordinal];
    if (entry is! Map) throw _invalidRender('A render input is not readable.');
    final name = entry['name'];
    final assetId = entry['assetId'];
    if (name is! String || !_renderInputName.hasMatch(name)) {
      throw _invalidRender('A render input is not named by the render.');
    }
    if (!names.add(name)) {
      throw _invalidRender('A render names the same input twice.');
    }
    if (assetId is! String || assetId.isEmpty || assetId.length > 200) {
      throw _invalidRender('A render input does not name stored media.');
    }
    references.add(
      WorkflowSourceReference(
        assetId: assetId,
        inputField: workflowRenderManifestInput,
        role: name,
        ordinal: ordinal,
      ),
    );
  }
  return references;
}

ApiError _invalidRender(String message) =>
    ApiError(400, 'invalid_render_manifest', message);

List<WorkflowSourceReference> _legacyReferences(Map<String, Object?> inputs) {
  final result = <WorkflowSourceReference>[];
  for (final entry in const <(String, String?, String?)>[
    ('source_asset_id', null, null),
    ('source_asset_id_2', null, null),
    ('source_asset_id_3', null, null),
    ('voice_reference_asset_id', 'audio', 'audio_reference'),
  ]) {
    final value = inputs[entry.$1];
    if (value == null || value == '') continue;
    if (value is! String) {
      throw const ApiError(
        409,
        'source_asset_not_ready',
        'The source asset is not ready for this workflow.',
      );
    }
    result.add(
      WorkflowSourceReference(
        assetId: value,
        inputField: entry.$1,
        kind: entry.$2,
        role: entry.$3,
        ordinal: result.length,
      ),
    );
  }
  return result;
}

void _validateCounts(List<WorkflowSourceReference> references) {
  int count(String kind) =>
      references.where((item) => item.kind == kind).length;
  if (count('image') > 9 || count('video') > 3 || count('audio') > 3) {
    throw _invalidManifest(
      'References exceed the MiniMax H3 image, video, or audio limit.',
    );
  }
}

void _validateMode(
  Map<String, Object?> manifest,
  Map<String, Object?> inputs,
  String mode,
  List<WorkflowSourceReference> references,
) {
  bool hasRole(String role) => references.any((item) => item.role == role);
  int countRole(String role) =>
      references.where((item) => item.role == role).length;
  if (mode != 'video_edit' &&
      (manifest.containsKey('edit_operation') ||
          manifest.containsKey('identity_replacement_consent'))) {
    throw _invalidManifest('Only video editing accepts edit fields.');
  }
  switch (mode) {
    case 'text_to_video':
      if (references.isNotEmpty) {
        throw _invalidManifest('Text-to-video cannot include references.');
      }
    case 'first_frame_to_video':
      if (references.length != 1 || !hasRole('first_frame')) {
        throw _invalidManifest('First-frame mode requires one first frame.');
      }
    case 'last_frame_to_video':
      if (references.length != 1 || !hasRole('last_frame')) {
        throw _invalidManifest('Last-frame mode requires one last frame.');
      }
    case 'first_last_frame_to_video':
      if (references.length != 2 ||
          !hasRole('first_frame') ||
          !hasRole('last_frame')) {
        throw _invalidManifest(
          'First-and-last-frame mode requires both endpoint frames.',
        );
      }
    case 'reference_to_video':
      if (references.isEmpty) {
        throw _invalidManifest('Reference-to-video requires a reference.');
      }
    case 'video_edit':
      if (countRole('source_video') != 1) {
        throw _invalidManifest('Video editing requires one source video.');
      }
      final operation = manifest['edit_operation'];
      if (operation is! String || !_editOperations.contains(operation)) {
        throw _invalidManifest('The MiniMax H3 edit operation is invalid.');
      }
      final consent = manifest['identity_replacement_consent'];
      if (consent is! bool) {
        throw _invalidManifest(
          'The identity replacement consent field is required.',
        );
      }
      if (operation == 'character_replacement' && !consent) {
        throw _invalidManifest(
          'Character replacement requires permission confirmation.',
        );
      }
      if (operation == 'character_replacement' &&
          !hasRole('subject') &&
          !hasRole('video_subject')) {
        throw _invalidManifest(
          'Character replacement requires a subject reference.',
        );
      }
      final declaredOperation = inputs['edit_operation'];
      final declaredConsent = inputs['identity_replacement_consent'];
      if ((declaredOperation != null && declaredOperation != operation) ||
          (declaredConsent != null && declaredConsent != consent.toString())) {
        throw _invalidManifest('The video edit fields do not match.');
      }
    case 'video_continue':
      if (countRole('source_video') != 1) {
        throw _invalidManifest('Video continuation requires one source video.');
      }
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw _invalidManifest('The reference manifest structure is invalid.');
}

void _requireKeys(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw _invalidManifest('The reference manifest has an unknown field.');
  }
}

ApiError _invalidManifest(String message) =>
    ApiError(400, 'invalid_reference_manifest', message);

final _assetIdPattern = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-'
  r'[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
);

const _modes = {
  'text_to_video',
  'first_frame_to_video',
  'last_frame_to_video',
  'first_last_frame_to_video',
  'reference_to_video',
  'video_edit',
  'video_continue',
};

const _roles = <String, String>{
  'first_frame': 'image',
  'last_frame': 'image',
  'subject': 'image',
  'style': 'image',
  'environment': 'image',
  'pose_reference': 'image',
  'effect_reference': 'image',
  'source_video': 'video',
  'motion_reference': 'video',
  'video_subject': 'video',
  'video_style': 'video',
  'video_environment': 'video',
  'video_action': 'video',
  'video_effect': 'video',
  'audio_reference': 'audio',
  'audio_reuse': 'audio',
};

const _editOperations = {
  'general_edit',
  'character_replacement',
  'object_replacement',
  'motion_transfer',
  'background_replacement',
};

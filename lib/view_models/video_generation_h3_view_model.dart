part of 'video_generation_view_model.dart';

extension MiniMaxH3VideoGeneration on VideoGenerationViewModel {
  bool get supportsH3PerformanceMode =>
      isMiniMaxH3 &&
      selectedTemplate!.inputs.containsKey(minimaxH3PerformanceModeInput);

  bool get supportsH3ReferenceInputs =>
      isMiniMaxH3 &&
      selectedTemplate!.inputs.containsKey(minimaxH3GenerationModeInput) &&
      selectedTemplate!.inputs.containsKey(minimaxH3ReferenceManifestInput);

  bool get supportsH3VideoEditing =>
      supportsH3ReferenceInputs &&
      selectedTemplate!.inputs.containsKey(minimaxH3EditOperationInput) &&
      selectedTemplate!.inputs.containsKey(minimaxH3IdentityConsentInput);

  bool h3ModeEnabled(MiniMaxH3GenerationMode mode) => switch (mode) {
    MiniMaxH3GenerationMode.textToVideo => true,
    MiniMaxH3GenerationMode.videoEdit => supportsH3VideoEditing,
    _ => supportsH3ReferenceInputs,
  };

  List<MiniMaxH3GenerationMode> get availableH3Modes => MiniMaxH3GenerationMode
      .values
      .where(h3ModeEnabled)
      .toList(growable: false);

  bool h3PerformanceModeEnabled(MiniMaxH3PerformanceMode mode) =>
      switch (mode) {
        MiniMaxH3PerformanceMode.quality => true,
        MiniMaxH3PerformanceMode.turbo =>
          h3Mode != MiniMaxH3GenerationMode.referenceToVideo &&
              h3Mode != MiniMaxH3GenerationMode.videoEdit &&
              h3Mode != MiniMaxH3GenerationMode.videoContinue,
      };

  List<MiniMaxH3ReferenceKind> get allowedH3ReferenceKinds => switch (h3Mode) {
    MiniMaxH3GenerationMode.textToVideo => const [],
    MiniMaxH3GenerationMode.firstFrame ||
    MiniMaxH3GenerationMode.lastFrame ||
    MiniMaxH3GenerationMode.firstLastFrame => const [
      MiniMaxH3ReferenceKind.image,
    ],
    MiniMaxH3GenerationMode.referenceToVideo ||
    MiniMaxH3GenerationMode.videoEdit ||
    MiniMaxH3GenerationMode.videoContinue => MiniMaxH3ReferenceKind.values,
  };

  String get h3ReferenceRequirement => switch (h3Mode) {
    MiniMaxH3GenerationMode.textToVideo => 'No reference media is required.',
    MiniMaxH3GenerationMode.firstFrame =>
      'Add one image to use as the opening frame.',
    MiniMaxH3GenerationMode.lastFrame =>
      'Add one image to use as the final frame.',
    MiniMaxH3GenerationMode.firstLastFrame =>
      'Add the opening image first, then the final image.',
    MiniMaxH3GenerationMode.referenceToVideo =>
      'Add at least one image, video, or audio reference.',
    MiniMaxH3GenerationMode.videoEdit =>
      'Add a source video, then optional subject, style, motion, or audio references.',
    MiniMaxH3GenerationMode.videoContinue =>
      'Add one source video, then optional subject, style, motion, environment, effect, or audio references.',
  };

  void setH3Mode(MiniMaxH3GenerationMode mode) {
    if (!isMiniMaxH3 || !h3ModeEnabled(mode) || h3Mode == mode) return;
    h3Mode = mode;
    if (!h3PerformanceModeEnabled(h3PerformanceMode)) {
      h3PerformanceMode = MiniMaxH3PerformanceMode.quality;
    }
    h3References.clear();
    h3EditOperation = MiniMaxH3EditOperation.general;
    identityReplacementConsent = false;
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  void setH3PerformanceMode(MiniMaxH3PerformanceMode mode) {
    if (!supportsH3PerformanceMode ||
        !h3PerformanceModeEnabled(mode) ||
        h3PerformanceMode == mode) {
      return;
    }
    h3PerformanceMode = mode;
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  void setH3EditOperation(MiniMaxH3EditOperation operation) {
    if (!supportsH3VideoEditing || h3EditOperation == operation) return;
    h3EditOperation = operation;
    if (operation != MiniMaxH3EditOperation.characterReplacement) {
      identityReplacementConsent = false;
    }
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  void setIdentityReplacementConsent(bool value) {
    if (!supportsH3VideoEditing) return;
    identityReplacementConsent = value;
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  bool addH3Reference({
    required MiniMaxH3ReferenceKind kind,
    required String filename,
    required Uint8List bytes,
  }) {
    if (!supportsH3ReferenceInputs || !allowedH3ReferenceKinds.contains(kind)) {
      setError(
        const FormatException(
          'This MiniMax H3 mode does not accept that reference type.',
        ),
      );
      return false;
    }
    final contentType = _contentTypeFor(kind, filename, bytes);
    final maximumBytes = _maximumBytesFor(kind);
    if (bytes.isEmpty || bytes.length > maximumBytes || contentType == null) {
      setError(
        FormatException(
          'Select a supported ${kind.name} file under '
          '${maximumBytes ~/ (1024 * 1024)} MB.',
        ),
      );
      return false;
    }
    if (_referenceLimitReached(kind)) {
      setError(
        const FormatException(
          'The MiniMax H3 reference limit has been reached for this mode.',
        ),
      );
      return false;
    }
    h3References.add(
      MiniMaxH3ReferenceDraft(
        id: 'reference-${_referenceSequence++}',
        filename: filename,
        bytes: bytes,
        contentType: contentType,
        kind: kind,
        role: _defaultRoleFor(kind),
      ),
    );
    submittedJob = null;
    setError(null);
    notifyListeners();
    return true;
  }

  bool addUploadedH3Reference({
    required MiniMaxH3ReferenceKind kind,
    required MiniMaxH3ReferenceRole role,
    required String filename,
    required String contentType,
    required String assetId,
  }) {
    if (!supportsH3ReferenceInputs ||
        !allowedH3ReferenceKinds.contains(kind) ||
        role.kind != kind ||
        !_sourceAssetIdPattern.hasMatch(assetId) ||
        _referenceLimitReached(kind)) {
      setError(
        const FormatException(
          'The uploaded MiniMax H3 reference is not valid for this mode.',
        ),
      );
      return false;
    }
    h3References.add(
      MiniMaxH3ReferenceDraft.uploaded(
        id: 'reference-${_referenceSequence++}',
        filename: filename,
        contentType: contentType,
        kind: kind,
        role: role,
        assetId: assetId,
      ),
    );
    submittedJob = null;
    setError(null);
    notifyListeners();
    return true;
  }

  void setH3ReferenceRole(String id, MiniMaxH3ReferenceRole role) {
    final index = h3References.indexWhere((item) => item.id == id);
    if (index < 0 || h3References[index].kind != role.kind) return;
    h3References[index] = h3References[index].copyWith(role: role);
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  void removeH3Reference(String id) {
    h3References.removeWhere((item) => item.id == id);
    submittedJob = null;
    setError(null);
    notifyListeners();
  }

  String h3ReferenceLabel(MiniMaxH3ReferenceDraft reference) {
    final index = h3References
        .where((item) => item.kind == reference.kind)
        .toList(growable: false)
        .indexWhere((item) => item.id == reference.id);
    final type = switch (reference.kind) {
      MiniMaxH3ReferenceKind.image => 'Picture',
      MiniMaxH3ReferenceKind.video => 'Video',
      MiniMaxH3ReferenceKind.audio => 'Audio',
    };
    return '<$type ${index + 1}>';
  }

  String? _contentTypeFor(
    MiniMaxH3ReferenceKind kind,
    String filename,
    Uint8List bytes,
  ) => switch (kind) {
    MiniMaxH3ReferenceKind.image => sourceImageContentType(bytes),
    MiniMaxH3ReferenceKind.video => sourceVideoContentType(
      bytes,
      filename: filename,
    ),
    MiniMaxH3ReferenceKind.audio => sourceAudioContentType(
      bytes,
      filename: filename,
    ),
  };

  int _maximumBytesFor(MiniMaxH3ReferenceKind kind) => switch (kind) {
    MiniMaxH3ReferenceKind.image => MiniMaxH3GenerationSpec.maximumImageBytes,
    MiniMaxH3ReferenceKind.video => MiniMaxH3GenerationSpec.maximumVideoBytes,
    MiniMaxH3ReferenceKind.audio => MiniMaxH3GenerationSpec.maximumAudioBytes,
  };

  bool _referenceLimitReached(MiniMaxH3ReferenceKind kind) {
    final kindCount = h3References.where((item) => item.kind == kind).length;
    final kindLimit = switch (kind) {
      MiniMaxH3ReferenceKind.image => MiniMaxH3GenerationSpec.maximumImages,
      MiniMaxH3ReferenceKind.video => MiniMaxH3GenerationSpec.maximumVideos,
      MiniMaxH3ReferenceKind.audio => MiniMaxH3GenerationSpec.maximumAudioFiles,
    };
    return h3References.length >= MiniMaxH3GenerationSpec.maximumReferences ||
        kindCount >= kindLimit ||
        _endpointModeIsFull;
  }

  bool get _endpointModeIsFull {
    final maximum = switch (h3Mode) {
      MiniMaxH3GenerationMode.firstFrame ||
      MiniMaxH3GenerationMode.lastFrame => 1,
      MiniMaxH3GenerationMode.firstLastFrame => 2,
      _ => MiniMaxH3GenerationSpec.maximumReferences,
    };
    return h3References.length >= maximum;
  }

  MiniMaxH3ReferenceRole _defaultRoleFor(MiniMaxH3ReferenceKind kind) {
    if (h3Mode == MiniMaxH3GenerationMode.firstFrame) {
      return MiniMaxH3ReferenceRole.firstFrame;
    }
    if (h3Mode == MiniMaxH3GenerationMode.lastFrame) {
      return MiniMaxH3ReferenceRole.lastFrame;
    }
    if (h3Mode == MiniMaxH3GenerationMode.firstLastFrame) {
      return h3References.isEmpty
          ? MiniMaxH3ReferenceRole.firstFrame
          : MiniMaxH3ReferenceRole.lastFrame;
    }
    return switch (kind) {
      MiniMaxH3ReferenceKind.image => MiniMaxH3ReferenceRole.subject,
      MiniMaxH3ReferenceKind.video =>
        (h3Mode == MiniMaxH3GenerationMode.videoEdit ||
                    h3Mode == MiniMaxH3GenerationMode.videoContinue) &&
                !h3References.any(
                  (item) => item.role == MiniMaxH3ReferenceRole.sourceVideo,
                )
            ? MiniMaxH3ReferenceRole.sourceVideo
            : MiniMaxH3ReferenceRole.motionReference,
      MiniMaxH3ReferenceKind.audio => MiniMaxH3ReferenceRole.audioReference,
    };
  }

  bool _validateH3References() {
    bool hasRole(MiniMaxH3ReferenceRole role) =>
        h3References.any((item) => item.role == role);
    int countRole(MiniMaxH3ReferenceRole role) =>
        h3References.where((item) => item.role == role).length;
    final valid = switch (h3Mode) {
      MiniMaxH3GenerationMode.textToVideo => h3References.isEmpty,
      MiniMaxH3GenerationMode.firstFrame =>
        h3References.length == 1 && hasRole(MiniMaxH3ReferenceRole.firstFrame),
      MiniMaxH3GenerationMode.lastFrame =>
        h3References.length == 1 && hasRole(MiniMaxH3ReferenceRole.lastFrame),
      MiniMaxH3GenerationMode.firstLastFrame =>
        h3References.length == 2 &&
            hasRole(MiniMaxH3ReferenceRole.firstFrame) &&
            hasRole(MiniMaxH3ReferenceRole.lastFrame),
      MiniMaxH3GenerationMode.referenceToVideo => h3References.isNotEmpty,
      MiniMaxH3GenerationMode.videoEdit =>
        countRole(MiniMaxH3ReferenceRole.sourceVideo) == 1,
      MiniMaxH3GenerationMode.videoContinue =>
        countRole(MiniMaxH3ReferenceRole.sourceVideo) == 1,
    };
    if (!valid) {
      setError(FormatException(h3ReferenceRequirement));
      return false;
    }
    if (h3Mode == MiniMaxH3GenerationMode.videoEdit &&
        h3EditOperation == MiniMaxH3EditOperation.characterReplacement &&
        (!(hasRole(MiniMaxH3ReferenceRole.subject) ||
                hasRole(MiniMaxH3ReferenceRole.videoSubject)) ||
            !identityReplacementConsent)) {
      setError(
        const FormatException(
          'Character replacement requires a subject reference and confirmation that you have permission to use the identity.',
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _appendH3Inputs(Map<String, Object?> input) async {
    if (!isMiniMaxH3) return;
    final templateInputs = selectedTemplate!.inputs;
    if (templateInputs.containsKey(minimaxH3PerformanceModeInput)) {
      input[minimaxH3PerformanceModeInput] = h3PerformanceMode.wireValue;
    }
    if (templateInputs.containsKey(minimaxH3GenerationModeInput)) {
      input[minimaxH3GenerationModeInput] = h3Mode.wireValue;
    }
    if (h3Mode == MiniMaxH3GenerationMode.videoContinue &&
        templateInputs.containsKey(minimaxH3ExtensionMethodInput)) {
      input[minimaxH3ExtensionMethodInput] = h3ExtensionMethod.wireValue;
    }
    if (templateInputs.containsKey(minimaxH3ReferenceManifestInput)) {
      await _uploadH3References();
      input[minimaxH3ReferenceManifestInput] =
          MiniMaxH3GenerationSpec.encodeManifest(
            mode: h3Mode,
            references: h3References,
            editOperation: h3EditOperation,
            identityReplacementConsent: identityReplacementConsent,
          );
    }
    if (h3Mode != MiniMaxH3GenerationMode.videoEdit) return;
    if (templateInputs.containsKey(minimaxH3EditOperationInput)) {
      input[minimaxH3EditOperationInput] = h3EditOperation.wireValue;
    }
    if (templateInputs.containsKey(minimaxH3IdentityConsentInput)) {
      input[minimaxH3IdentityConsentInput] = identityReplacementConsent;
    }
  }

  Future<void> _uploadH3References() async {
    for (var index = 0; index < h3References.length; index++) {
      final reference = h3References[index];
      if (reference.assetId != null) continue;
      busyLabel = 'Uploading reference ${index + 1} of ${h3References.length}';
      notifyListeners();
      final assetId = await _sourceAssets.upload(
        workspaceId: workspaceId,
        expectedBucket: expectedBucket,
        filename: reference.filename,
        bytes: reference.bytes,
        contentType: reference.contentType,
        ghostMode: ghostMode,
      );
      h3References[index] = reference.copyWith(assetId: assetId);
    }
    busyLabel = 'Launching job';
    notifyListeners();
  }
}

final RegExp _sourceAssetIdPattern = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-'
  r'[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
);

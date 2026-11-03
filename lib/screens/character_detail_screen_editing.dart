part of 'character_detail_screen.dart';

extension _CharacterDetailEditing on _CharacterDetailScreenState {
  void _openSheetEditor(CharacterSheetEditMode mode) {
    _editPrompt.clear();
    _enhancements.fields.reset();
    _update(() {
      _editMode = mode;
      _editRequest = null;
      _editPreview = null;
    });
  }

  /// The rewrite affordance for a character sheet edit.
  ///
  /// Names no model. The workflow id is what selects the guide, and the person
  /// tweaking their character sheet owns a character, not a checkpoint -- rule
  /// 12 keeps the mechanism out of what they read.
  PromptEnhanceBinding? get _sheetEditEnhanceBinding {
    final mode = _editMode;
    if (mode == null) return null;
    final area = mode == CharacterSheetEditMode.area;
    return _enhancements.binding(
      field: 'prompt',
      stateKey: _sheetEditEnhancementKey(mode),
      workflowId: area ? 'image-inpaint-qwen' : 'image-edit-qwen-2511',
      targetModel: '',
      modality: area ? 'inpaint' : 'image_edit',
      maxLength: 4000,
      attachedImageCount: 1,
    );
  }

  void _closeSheetEditor() {
    _editPrompt.clear();
    _enhancements.fields.reset();
    _update(() {
      _editMode = null;
      _editRequest = null;
      _editPreview = null;
    });
  }

  Future<void> _generateSheetEdit(List<Rect> masks) async {
    final mode = _editMode;
    final prompt = _editPrompt.text.trim();
    final before = _selectedImage(_bodyImages);
    if (mode == null || prompt.isEmpty || before == null) return;
    if (mode == CharacterSheetEditMode.area && masks.isEmpty) return;
    await _dispatchSheetEdit(
      _CharacterSheetEditRequest(
        mode: mode,
        prompt: prompt,
        masks: List<Rect>.of(masks),
        before: before,
      ),
    );
  }

  Future<void> _dispatchSheetEdit(_CharacterSheetEditRequest request) async {
    _update(() {
      _generating = true;
      _editMode = request.mode;
      _editRequest = request.withJobId(null);
      _editPreview = null;
    });
    try {
      final source = await widget.controller.api.post(
        '$_path/selected-image-source',
      );
      final assetId = source['assetId'] as String? ?? '';
      if (assetId.isEmpty) {
        throw const FormatException('Selected sheet source was unavailable.');
      }
      final response = await widget.controller.api.post(
        request.mode == CharacterSheetEditMode.area
            ? '$_path/inpaint-sheet'
            : '$_path/edit-sheet',
        body: {
          'sourceAssetId': assetId,
          'prompt': request.prompt,
          if (_enhancements.fields.keptEnhancedTextFor(
            _sheetEditEnhancementKey(request.mode),
          ))
            'promptEnhancementBypass': 'user_enhanced',
          if (request.mode == CharacterSheetEditMode.area)
            'maskRegions': encodeInpaintMaskRegions(request.masks),
        },
      );
      final data = asJsonMap(response['data']);
      final character = CharacterModel.fromJson(asJsonMap(data['character']));
      final job = asJsonMap(data['job']);
      if (!mounted) return;
      _update(() {
        _character = character;
        _bodyGeneration = job;
        _editRequest = request.withJobId(job['jobId'] as String?);
      });
      widget.onSaved(character);
      await _loadImages(body: true);
      final jobId = job['jobId'];
      if (jobId is String && jobId.isNotEmpty) {
        _generationWatcher.watch(jobId);
      }
    } on Object catch (error) {
      if (mounted) {
        _update(() => _editRequest = null);
        showFailure(context, error);
      }
    } finally {
      if (mounted) _update(() => _generating = false);
    }
  }

  Future<bool> _handleCompletedImage(
    CharacterImageModel image,
    JsonMap job,
  ) async {
    final review = asJsonMap(job['generationReview']);
    if (review['kind'] != 'character_sheet_edit') {
      return _selectImage(image, showError: false);
    }
    final existing = _editRequest;
    final before = existing?.before ?? _selectedImage(_bodyImages);
    if (before == null) return false;
    final request = existing?.jobId == image.jobId
        ? existing!
        : _editRequestFromJob(job, before);
    if (!mounted) return false;
    _editPrompt.text = request.prompt;
    _update(() {
      _editMode = request.mode;
      _editRequest = request;
      _editPreview = image;
    });
    return true;
  }

  void _handleGenerationChanged(JsonMap job) {
    if (!mounted) return;
    final review = asJsonMap(job['generationReview']);
    _CharacterSheetEditRequest? restored;
    if (review['kind'] == 'character_sheet_edit' && _editRequest == null) {
      final before = _selectedImage(_bodyImages);
      if (before != null) restored = _editRequestFromJob(job, before);
    }
    if (restored != null) _editPrompt.text = restored.prompt;
    _update(() {
      _bodyGeneration = job;
      if (restored != null) {
        _editMode = restored.mode;
        _editRequest = restored;
      }
    });
  }

  _CharacterSheetEditRequest _editRequestFromJob(
    JsonMap job,
    CharacterImageModel before,
  ) {
    final review = asJsonMap(job['generationReview']);
    final inputs = asJsonMap(job['inputs']);
    final mode = review['mode'] == 'area'
        ? CharacterSheetEditMode.area
        : CharacterSheetEditMode.wholeSheet;
    return _CharacterSheetEditRequest(
      mode: mode,
      prompt:
          inputs['prompt'] as String? ?? 'Edit the selected character sheet.',
      masks: mode == CharacterSheetEditMode.area
          ? decodeInpaintMaskRegions(inputs['mask_regions'])
          : const [],
      before: before,
      jobId: job['jobId'] as String?,
    );
  }

  Future<void> _keepEditPreview() async {
    final preview = _editPreview;
    if (preview == null) return;
    _update(() => _reviewActionBusy = true);
    final kept = await _selectImage(preview);
    if (kept) _editPrompt.clear();
    if (mounted) _update(() => _reviewActionBusy = false);
  }

  Future<void> _tryEditAgain() async {
    final preview = _editPreview;
    final request = _editRequest;
    if (preview == null || request == null) return;
    _update(() => _reviewActionBusy = true);
    final removed = await _removeCharacterImage(preview);
    if (removed && mounted) {
      _update(() => _editPreview = null);
      await _dispatchSheetEdit(request.withJobId(null));
    }
    if (mounted) _update(() => _reviewActionBusy = false);
  }

  Future<void> _discardEditPreview() async {
    final preview = _editPreview;
    if (preview == null) return;
    _update(() => _reviewActionBusy = true);
    final removed = await _removeCharacterImage(preview);
    if (removed && mounted) {
      _editPrompt.clear();
      _update(() {
        _editMode = null;
        _editRequest = null;
        _editPreview = null;
        _bodyGeneration = null;
      });
    }
    if (mounted) _update(() => _reviewActionBusy = false);
  }
}

String _sheetEditEnhancementKey(CharacterSheetEditMode mode) =>
    mode == CharacterSheetEditMode.area ? 'sheet-inpaint' : 'sheet-edit';

class _CharacterSheetEditRequest {
  const _CharacterSheetEditRequest({
    required this.mode,
    required this.prompt,
    required this.masks,
    required this.before,
    this.jobId,
  });

  final CharacterSheetEditMode mode;
  final String prompt;
  final List<Rect> masks;
  final CharacterImageModel before;
  final String? jobId;

  _CharacterSheetEditRequest withJobId(String? value) =>
      _CharacterSheetEditRequest(
        mode: mode,
        prompt: prompt,
        masks: masks,
        before: before,
        jobId: value,
      );
}

bool _sameImage(CharacterImageModel left, CharacterImageModel right) =>
    left.jobId == right.jobId &&
    left.path == right.path &&
    left.generation == right.generation;

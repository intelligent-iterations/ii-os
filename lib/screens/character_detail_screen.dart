import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../models/character_generation_state.dart';
import '../models/inpaint_mask.dart';
import '../models/models.dart';
import '../services/character_generation_watcher.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/character_design_regions.dart';
import '../widgets/character_delete_dialog.dart';
import '../widgets/character_designer.dart';
import '../widgets/character_detail_footer.dart';
import '../widgets/character_essentials.dart';
import '../widgets/character_historical_picker.dart';
import '../widgets/character_questionnaire.dart';
import '../widgets/character_selected_sheet.dart';
import '../widgets/character_sheet_edit_composer.dart';
import '../widgets/common.dart';
import '../widgets/job_submission_result.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../state/prompt_enhance_host.dart';
import '../state/prompt_enhancement_fields.dart';
import '../widgets/prompt_enhance_bar.dart';

part 'character_detail_screen_editing.dart';

class CharacterDetailScreen extends StatefulWidget {
  const CharacterDetailScreen({
    required this.controller,
    required this.character,
    required this.canWrite,
    this.initialGeneration,
    this.initialBodyGeneration,
    this.initialImages,
    required this.onSaved,
    required this.onDeleted,
    required this.onClose,
    super.key,
  });

  final AppController controller;
  final CharacterModel character;
  final bool canWrite;
  final JsonMap? initialGeneration;
  final JsonMap? initialBodyGeneration;
  final List<CharacterImageModel>? initialImages;
  final ValueChanged<CharacterModel> onSaved;
  final VoidCallback onDeleted;
  final VoidCallback onClose;

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  void _update(VoidCallback change) => setState(change);

  late CharacterModel _character = widget.character;
  late final TextEditingController _name = TextEditingController(
    text: widget.character.name == 'Untitled character'
        ? ''
        : widget.character.name,
  );
  late final TextEditingController _editPrompt = TextEditingController();
  late final PromptEnhanceHost _enhancements = PromptEnhanceHost(
    fields: PromptEnhancementFields(
      repository: PromptEnhancementApiRepository(widget.controller.api),
      workspaceId: widget.controller.workspace!.id,
    ),
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  late final Map<String, TextEditingController> _answers = {
    for (final question in characterQuestions)
      question.key: TextEditingController(
        text: widget.character.answers[question.key] ?? '',
      ),
  };
  late final Map<String, TextEditingController> _bodyAnswers = {
    for (final question in characterBodyQuestions)
      question.key: TextEditingController(
        text: widget.character.bodyAnswers[question.key] ?? '',
      ),
  };
  late final Map<String, TextEditingController> _clothingAnswers = {
    for (final question in characterClothingQuestions)
      question.key: TextEditingController(
        text: widget.character.clothingAnswers[question.key] ?? '',
      ),
  };
  late List<CharacterImageModel> _bodyImages = widget.initialImages ?? const [];
  late bool _bodyImagesLoading = widget.initialImages == null;
  late JsonMap? _bodyGeneration = widget.initialBodyGeneration;
  late final CharacterGenerationWatcher _generationWatcher;
  bool _saving = false;
  bool _deleting = false;
  bool _generating = false;
  bool _dirty = false;
  bool _reviewActionBusy = false;
  CharacterSheetEditMode? _editMode;
  _CharacterSheetEditRequest? _editRequest;
  CharacterImageModel? _editPreview;
  String? _saveError;
  String? _selectingPath;

  @override
  void initState() {
    super.initState();
    _generationWatcher = CharacterGenerationWatcher(
      controller: widget.controller,
      workspaceId: widget.controller.workspace!.id,
      loadImages: () => _loadImages(body: true),
      handleCompletedImage: _handleCompletedImage,
      refreshCharacter: _refreshCharacter,
      onJobChanged: _handleGenerationChanged,
    );
    unawaited(_loadImages(body: true));
    final jobId =
        _bodyGeneration?['jobId'] ?? _character.lastBodyGenerationJobId;
    if (jobId is String && jobId.isNotEmpty) {
      _generationWatcher.watch(jobId);
    }
  }

  @override
  void dispose() {
    _generationWatcher.dispose();
    _name.dispose();
    _editPrompt.dispose();
    for (final controller in _answers.values) {
      controller.dispose();
    }
    for (final controller in _bodyAnswers.values) {
      controller.dispose();
    }
    for (final controller in _clothingAnswers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSheet = _selectedImage(_bodyImages);
    final hasVisibleSheet =
        selectedSheet != null &&
        (selectedSheet.hasReadGrant || selectedSheet.url.trim().isNotEmpty);
    final preview = _editPreview;
    final editRequest = _editRequest;
    final historicalImages = preview == null
        ? _bodyImages
        : _bodyImages.where((image) => !_sameImage(image, preview)).toList();
    return PageFrame(
      title: _character.name,
      subtitle:
          'Refine the character, generate sheets, then choose the representative character sheet.',
      actions: [
        TextButton.icon(
          onPressed: _busy ? null : widget.onClose,
          icon: const Icon(LucideIcons.arrowLeft, size: 17),
          label: const Text('Characters'),
        ),
        if (widget.canWrite)
          OutlinedButton.icon(
            onPressed: _busy ? null : _confirmDelete,
            icon: _deleting
                ? const CharacterProgressIcon()
                : const Icon(LucideIcons.trash2, size: 17),
            label: const Text('Delete'),
          ),
      ],
      stickyFooter: CharacterDetailFooter(
        canSave: widget.canWrite && _dirty && !_busy,
        canGenerate: _canGenerateCurrent && !_busy && !_generationInFlight,
        saving: _saving,
        generating: _generating,
        generateLabel: 'Generate full-body sheet',
        onSave: _save,
        onGenerate: _generate,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preview != null && editRequest != null)
            CharacterSheetEditReview(
              appController: widget.controller,
              mode: editRequest.mode,
              before: editRequest.before,
              after: preview,
              prompt: editRequest.prompt,
              busy: _reviewActionBusy,
              onKeep: _keepEditPreview,
              onTryAgain: _tryEditAgain,
              onDiscard: _discardEditPreview,
            )
          else if (_editMode != null && selectedSheet != null)
            CharacterSheetEditComposer(
              appController: widget.controller,
              mode: _editMode!,
              image: selectedSheet,
              controller: _editPrompt,
              initialMasks: editRequest?.masks ?? const [],
              enabled:
                  widget.canWrite &&
                  !_busy &&
                  !_generationInFlight &&
                  !_editBusy,
              busy: _editBusy,
              onChanged: (_) => setState(() {}),
              promptEnhance: _sheetEditEnhanceBinding,
              onSubmit:
                  widget.canWrite &&
                      !_busy &&
                      !_generationInFlight &&
                      !_editBusy &&
                      _editPrompt.text.trim().isNotEmpty
                  ? _generateSheetEdit
                  : null,
              onCancel: _closeSheetEditor,
            )
          else
            CharacterSelectedSheet(
              controller: widget.controller,
              image: selectedSheet,
              generationStatus: _generating
                  ? 'dispatching'
                  : _activeGenerationStatus,
              generationJobId:
                  _activeGeneration?['jobId'] as String? ??
                  _character.lastBodyGenerationJobId,
              errorCode: _activeGenerationErrorCode,
              onRetry: _canGenerateCurrent && !_busy ? _generate : null,
              onTweakSheet:
                  hasVisibleSheet &&
                      widget.canWrite &&
                      !_busy &&
                      !_generationInFlight
                  ? () => _openSheetEditor(CharacterSheetEditMode.wholeSheet)
                  : null,
              onEditArea:
                  hasVisibleSheet &&
                      widget.canWrite &&
                      !_busy &&
                      !_generationInFlight
                  ? () => _openSheetEditor(CharacterSheetEditMode.area)
                  : null,
            ),
          if (hasVisibleSheet) IiOsGap.vMd,
          CharacterHistoricalPicker(
            controller: widget.controller,
            bodyImages: historicalImages,
            bodyLoading: _bodyImagesLoading,
            pendingJobId: _generating
                ? 'starting-${_character.id}'
                : pendingCharacterImageJobId(
                    jobId:
                        _activeGeneration?['jobId'] as String? ??
                        _character.lastBodyGenerationJobId,
                    status: _activeGenerationStatus,
                    images: _bodyImages,
                  ),
            canSelect:
                widget.canWrite &&
                !_busy &&
                !_generationInFlight &&
                preview == null,
            selectingPath: _selectingPath,
            onSelect: _selectImage,
            onRefresh: () => _loadImages(body: true),
            onDelete: _deleteImage,
          ),
          IiOsGap.vMd,
          if (_character.creationMode == 'scratch')
            CharacterEssentials(
              name: _name,
              answers: _answers,
              onChanged: _changed,
              enabled: widget.canWrite && !_busy,
            ),
          if (_character.creationMode == 'scratch') IiOsGap.vMd,
          if (_character.creationMode == 'scratch')
            LayoutBuilder(
              builder: (context, constraints) {
                final form = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CharacterDesigner(
                      kind: CharacterDesignKind.combined,
                      headAnswers: _answers,
                      bodyAnswers: _bodyAnswers,
                      clothingAnswers: _clothingAnswers,
                      onChanged: _changed,
                      enabled: widget.canWrite && !_busy,
                    ),
                  ],
                );
                final prompt = CharacterPromptPreview(
                  title: 'Full-body generation prompt',
                  prompt: _promptDetails(_character.bodyPrompt),
                  saving: _saving,
                  dirty: _dirty,
                  error: _saveError,
                  onRetry: _save,
                );
                if (constraints.maxWidth < 980) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [form, IiOsGap.vMd, prompt],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: form),
                    IiOsGap.hMd,
                    Expanded(flex: 4, child: prompt),
                  ],
                );
              },
            ),
          IiOsGap.vMd,
          if (_activeGeneration != null) ...[
            JobSubmissionResult(
              controller: widget.controller,
              result: _activeGeneration!,
              title: 'Character sheet generation',
            ),
            IiOsGap.vMd,
          ],
        ],
      ),
    );
  }

  bool get _busy => _saving || _deleting || _generating;
  bool get _generationInFlight =>
      isActiveCharacterGenerationStatus(_activeGenerationStatus);
  bool get _editBusy =>
      _editRequest != null &&
      _editPreview == null &&
      (_generating ||
          (_activeGenerationStatus != 'failed' &&
              _activeGenerationStatus != 'cancelled'));
  bool get _canGenerate =>
      widget.canWrite && widget.controller.can('jobs.trigger');

  bool get _canGenerateCurrent =>
      _canGenerate &&
      ((_character.isScratch && _character.bodyPrompt.trim().isNotEmpty) ||
          (_character.isImageBased &&
              _character.sourceAssetId?.trim().isNotEmpty == true));

  JsonMap? get _activeGeneration => _bodyGeneration;
  String? get _activeGenerationStatus =>
      _bodyGeneration?['status'] as String? ??
      _character.lastBodyGenerationStatus;
  String? get _activeGenerationErrorCode {
    final direct = _bodyGeneration?['errorCode'];
    if (direct is String && direct.isNotEmpty) return direct;
    final result = _bodyGeneration?['workflowResult'];
    if (result is Map) {
      final nested = result['errorCode'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
    return _character.lastBodyGenerationErrorCode;
  }

  String _promptDetails(String prompt) => prompt
      .replaceFirst(RegExp(r'^TEXT-TO-IMAGE FULL-BODY CHARACTER SHEET\s*'), '')
      .trim();

  void _changed() {
    if (!widget.canWrite) return;
    setState(() {
      _dirty = true;
      _saveError = null;
    });
  }

  Future<bool> _save() async {
    if (!_dirty) return true;
    setState(() => _saving = true);
    try {
      final response = await widget.controller.api.patch(
        _path,
        body: {
          'name': _name.text.trim().isEmpty
              ? 'Untitled character'
              : _name.text.trim(),
          'answers': {
            for (final entry in _answers.entries)
              entry.key: entry.value.text.trim(),
          },
          'bodyAnswers': {
            for (final entry in _bodyAnswers.entries)
              entry.key: entry.value.text.trim(),
          },
          'clothingAnswers': {
            for (final entry in _clothingAnswers.entries)
              entry.key: entry.value.text.trim(),
          },
        },
      );
      final saved = CharacterModel.fromJson(asJsonMap(response['data']));
      if (!mounted) return true;
      setState(() {
        _character = saved;
        _dirty = false;
        _saveError = null;
      });
      widget.onSaved(saved);
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generate() async {
    if (_dirty && !await _save()) return;
    if (!mounted) return;
    setState(() => _generating = true);
    try {
      final operation = _character.isImageBased
          ? 'generate-from-image'
          : 'generate-body';
      final response = await widget.controller.api.post('$_path/$operation');
      final data = asJsonMap(response['data']);
      final character = CharacterModel.fromJson(asJsonMap(data['character']));
      final job = asJsonMap(data['job']);
      if (!mounted) return;
      setState(() {
        _character = character;
        _bodyGeneration = job;
      });
      widget.onSaved(character);
      unawaited(widget.controller.refreshDashboard());
      unawaited(_loadImages(body: true));
      final jobId = job['jobId'];
      if (jobId is String && jobId.isNotEmpty) {
        _generationWatcher.watch(jobId);
      }
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<List<CharacterImageModel>> _loadImages({bool body = false}) async {
    if (mounted) {
      setState(() {
        if (body) {
          _bodyImagesLoading = true;
        }
      });
    }
    try {
      final response = await widget.controller.api.get(
        body ? '$_path/body-images' : '$_path/images',
      );
      final images = (response['images'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .map(CharacterImageModel.fromJson)
          .toList();
      if (mounted) {
        setState(() {
          if (body) {
            _bodyImages = images;
          }
        });
      }
      return images;
    } on Object {
      // Keep the existing references when a signed image history request fails.
      return _bodyImages;
    } finally {
      if (mounted) {
        setState(() {
          if (body) {
            _bodyImagesLoading = false;
          }
        });
      }
    }
  }

  Future<bool> _selectImage(
    CharacterImageModel image, {
    bool showError = true,
  }) async {
    if (!mounted) return false;
    final previousImages = _bodyImages;
    final previousMode = _editMode;
    final previousRequest = _editRequest;
    final previousPreview = _editPreview;
    setState(() {
      _selectingPath = image.path;
      _bodyImages = selectCharacterImageLocally(_bodyImages, image);
      _editMode = null;
      _editRequest = null;
      _editPreview = null;
    });
    try {
      final response = await widget.controller.api.patch(
        '$_path/selected-body-image',
        body: {
          'jobId': image.jobId,
          'path': image.path,
          'generation': image.generation,
        },
      );
      final character = CharacterModel.fromJson(asJsonMap(response['data']));
      if (!mounted) return false;
      setState(() => _character = character);
      widget.onSaved(character);
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _bodyImages = previousImages;
          _editMode = previousMode;
          _editRequest = previousRequest;
          _editPreview = previousPreview;
        });
        if (showError) showFailure(context, error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _selectingPath = null);
    }
  }

  Future<void> _deleteImage(CharacterImageModel image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete historical sheet?'),
        content: Text('Remove ${image.filename} from this character?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _removeCharacterImage(image);
  }

  Future<bool> _removeCharacterImage(CharacterImageModel image) async {
    try {
      final response = await widget.controller.api.delete(
        '$_path/body-images',
        body: {'jobId': image.jobId, 'path': image.path},
      );
      final character = CharacterModel.fromJson(asJsonMap(response['data']));
      if (!mounted) return false;
      setState(() => _character = character);
      widget.onSaved(character);
      await _loadImages(body: true);
      return true;
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
      return false;
    }
  }

  Future<void> _refreshCharacter() async {
    try {
      final response = await widget.controller.api.get(_path);
      final character = CharacterModel.fromJson(
        asJsonMap(response['character']),
      );
      if (!mounted) return;
      setState(() => _character = character);
      widget.onSaved(character);
    } on Object {
      // The terminal job result remains visible if character refresh is stale.
    }
  }

  Future<void> _confirmDelete() async {
    if (!await confirmCharacterDeletion(context, _character.name) || !mounted) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await widget.controller.api.delete(_path);
      if (mounted) widget.onDeleted();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String get _path =>
      'v1/workspaces/${widget.controller.workspace!.id}/characters/${_character.id}';

  CharacterImageModel? _selectedImage(List<CharacterImageModel> images) {
    for (final image in images) {
      if (image.selected) return image;
    }
    return null;
  }
}

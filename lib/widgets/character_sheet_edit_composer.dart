import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../services/client_error_reporter.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import 'character_image_preview.dart';
import 'image_edit_controls.dart';
import 'prompt_enhance_bar.dart';

enum CharacterSheetEditMode { wholeSheet, area }

class CharacterSheetEditComposer extends StatefulWidget {
  const CharacterSheetEditComposer({
    required this.mode,
    required this.image,
    this.appController,
    required this.controller,
    required this.enabled,
    required this.busy,
    this.initialMasks = const [],
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
    this.promptEnhance,
    super.key,
  });

  final CharacterSheetEditMode mode;
  final CharacterImageModel image;
  final AppController? appController;
  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final List<Rect> initialMasks;
  final ValueChanged<String> onChanged;
  final ValueChanged<List<Rect>>? onSubmit;
  final VoidCallback onCancel;

  /// Offers to rewrite the requested change against the guide for the model
  /// that will render it.
  final PromptEnhanceBinding? promptEnhance;

  @override
  State<CharacterSheetEditComposer> createState() =>
      _CharacterSheetEditComposerState();
}

class _CharacterSheetEditComposerState
    extends State<CharacterSheetEditComposer> {
  late List<Rect> _masks = List<Rect>.of(widget.initialMasks);
  double _aspectRatio = 16 / 9;
  Uint8List? _imageBytes;
  Object? _imageLoadError;
  int _loadEpoch = 0;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  bool get _isAreaEdit => widget.mode == CharacterSheetEditMode.area;
  bool get _canDescribe => !_isAreaEdit || _masks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadVerifiedImage();
  }

  @override
  void didUpdateWidget(covariant CharacterSheetEditComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.image.path != widget.image.path ||
        oldWidget.image.readUrl != widget.image.readUrl ||
        oldWidget.appController != widget.appController) {
      _masks = List<Rect>.of(widget.initialMasks);
      _aspectRatio = 16 / 9;
      _loadVerifiedImage();
    }
  }

  @override
  void dispose() {
    _loadEpoch++;
    _removeImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Card(
        key: const ValueKey('character-sheet-edit-composer'),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final canvas = _canvas();
                  final details = _details(context);
                  if (constraints.maxWidth < 860) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [canvas, IiOsGap.vMd, details],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: canvas),
                      IiOsGap.hLg,
                      Expanded(flex: 4, child: details),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isAreaEdit ? 'Edit an area' : 'Tweak entire sheet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            Text(
              _isAreaEdit
                  ? 'Select what you want to change. Add matching areas when the same feature appears in more than one view.'
                  : 'Describe one coordinated adjustment to the complete character sheet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Cancel edit',
        onPressed: widget.enabled && !widget.busy ? widget.onCancel : null,
        icon: const Icon(LucideIcons.x, size: 18),
      ),
    ],
  );

  Widget _canvas() {
    if (widget.busy) {
      return AspectRatio(
        aspectRatio: _aspectRatio.clamp(.45, 2.4).toDouble(),
        child: const DecoratedBox(
          key: ValueKey('character-edit-loading'),
          decoration: BoxDecoration(color: Color(0xfff7f7f5)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                IiOsGap.vSm,
                Text('Creating your edit preview\u2026'),
              ],
            ),
          ),
        ),
      );
    }
    if (widget.appController != null &&
        widget.image.hasReadGrant &&
        _imageBytes == null) {
      return AspectRatio(
        aspectRatio: _aspectRatio,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xfff7f7f5)),
          child: Center(
            child: _imageLoadError == null
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const Icon(LucideIcons.imageOff),
          ),
        ),
      );
    }
    if (!_isAreaEdit) {
      return ImageEditPreview(
        imageBytes: _imageBytes,
        imageUrl: null,
        aspectRatio: _aspectRatio,
      );
    }
    return InpaintRegionSelector(
      key: ValueKey('character-area-selector-${widget.image.path}'),
      imageBytes: _imageBytes,
      imageUrl: null,
      aspectRatio: _aspectRatio,
      masks: _masks,
      allowMultiple: true,
      enabled: widget.enabled,
      onChanged: (value) => setState(() => _masks = value),
      onClear: _masks.isEmpty ? null : () => setState(() => _masks = const []),
    );
  }

  Widget _details(BuildContext context) {
    if (widget.busy) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Creating preview',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          IiOsGap.vXs,
          Text(
            'The result will appear here for review. Your selected character sheet will not change until you keep the edit.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isAreaEdit) ...[
          Text(
            _masks.isEmpty
                ? 'No area selected'
                : _masks.length == 1
                ? 'Selected area'
                : 'Selected areas',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IiOsGap.vXxs,
          Text(
            _masks.isEmpty
                ? 'Drag a box on the character sheet to begin.'
                : 'Only the highlighted selection can change. Everything outside it will stay unchanged.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IiOsGap.vMd,
        ],
        if (_canDescribe) ...[
          TextField(
            key: const ValueKey('character-edit-prompt'),
            controller: widget.controller,
            minLines: 4,
            maxLines: 7,
            maxLength: 4000,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: _isAreaEdit
                  ? 'What should change here?'
                  : 'What should change?',
              hintText: _isAreaEdit
                  ? 'Make the white patch on the cat\u2019s chest smaller. Keep everything else unchanged.'
                  : 'Make the line work cleaner and keep the character design unchanged.',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.promptEnhance case final binding?)
            PromptEnhanceBar(
              controller: widget.controller,
              binding: binding,
              enabled: widget.enabled,
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('character-edit-submit'),
            onPressed: widget.onSubmit == null
                ? null
                : () => widget.onSubmit!(_masks),
            icon: const Icon(LucideIcons.wandSparkles, size: 16),
            label: const Text('Generate edit'),
          ),
        ],
      ],
    );
  }

  void _loadVerifiedImage() {
    final epoch = ++_loadEpoch;
    _removeImageListener();
    _imageBytes = null;
    _imageLoadError = null;
    final controller = widget.appController;
    if (controller == null || !widget.image.hasReadGrant) return;
    unawaited(
      controller
          .readCharacterImage(widget.image)
          .then(
            (media) {
              if (!mounted || epoch != _loadEpoch) return;
              setState(() => _imageBytes = media.bytes);
              _resolveImageSize(media.bytes);
            },
            onError: (Object error, StackTrace stackTrace) {
              unawaited(
                ClientErrorReporter.reportGlobal(
                  error,
                  stackTrace,
                  source: 'character.sheet_edit.verified',
                ),
              );
              if (mounted && epoch == _loadEpoch) {
                setState(() => _imageLoadError = error);
              }
            },
          ),
    );
  }

  void _resolveImageSize(Uint8List bytes) {
    _removeImageListener();
    final stream = MemoryImage(bytes).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      final width = info.image.width;
      final height = info.image.height;
      if (mounted && width > 0 && height > 0) {
        setState(() => _aspectRatio = width / height);
      }
    }, onError: (_, _) {});
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }
}

class CharacterSheetEditReview extends StatefulWidget {
  const CharacterSheetEditReview({
    required this.mode,
    required this.before,
    required this.after,
    this.appController,
    required this.prompt,
    required this.busy,
    required this.onKeep,
    required this.onTryAgain,
    required this.onDiscard,
    super.key,
  });

  final CharacterSheetEditMode mode;
  final CharacterImageModel before;
  final CharacterImageModel after;
  final AppController? appController;
  final String prompt;
  final bool busy;
  final VoidCallback onKeep;
  final VoidCallback onTryAgain;
  final VoidCallback onDiscard;

  @override
  State<CharacterSheetEditReview> createState() =>
      _CharacterSheetEditReviewState();
}

enum _ReviewImage { before, after }

class _CharacterSheetEditReviewState extends State<CharacterSheetEditReview> {
  _ReviewImage _visible = _ReviewImage.after;

  @override
  Widget build(BuildContext context) {
    final image = _visible == _ReviewImage.before
        ? widget.before
        : widget.after;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Card(
          key: const ValueKey('character-edit-review'),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.mode == CharacterSheetEditMode.area
                          ? 'Review area edit'
                          : 'Review sheet tweak',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SegmentedButton<_ReviewImage>(
                      segments: const [
                        ButtonSegment(
                          value: _ReviewImage.before,
                          label: Text('Before'),
                        ),
                        ButtonSegment(
                          value: _ReviewImage.after,
                          label: Text('After'),
                        ),
                      ],
                      selected: {_visible},
                      onSelectionChanged: widget.busy
                          ? null
                          : (value) => setState(() => _visible = value.first),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AspectRatio(
                  key: ValueKey('character-edit-review-${_visible.name}'),
                  aspectRatio: 16 / 9,
                  child: widget.appController == null
                      ? const ColoredBox(color: Color(0xfff7f7f5))
                      : CharacterVerifiedImage(
                          controller: widget.appController!,
                          image: image,
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.prompt,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('character-edit-discard'),
                      onPressed: widget.busy ? null : widget.onDiscard,
                      child: const Text('Discard'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('character-edit-try-again'),
                      onPressed: widget.busy ? null : widget.onTryAgain,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Try again'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('character-edit-keep'),
                      onPressed: widget.busy ? null : widget.onKeep,
                      icon: widget.busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.check, size: 16),
                      label: const Text('Keep this edit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

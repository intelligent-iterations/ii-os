import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../repositories/generation_history_repository.dart';
import '../services/picked_media_reader.dart';
import '../services/source_asset_uploader.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../widgets/voice_clone_reference_field.dart';

part 'narration_voice_line.dart';

class NarrationGenerationForm extends StatefulWidget {
  const NarrationGenerationForm({
    required this.canSubmit,
    required this.submitting,
    required this.onSubmit,
    required this.onUploadVoiceReference,
    required this.history,
    required this.loadLibraryPreview,
    required this.readLibraryMedia,
    this.promptEnhance,
    super.key,
  });

  /// Offers to make the script easier for the voice model to read aloud.
  final PromptEnhanceBinding? promptEnhance;

  final bool canSubmit;
  final bool submitting;
  final Future<void> Function({
    required String text,
    required String voiceModel,
    required String language,
    required String seed,
    String? voiceReferenceAssetId,
    bool voiceCloneConsent,
  })
  onSubmit;
  final Future<String> Function({
    required String filename,
    required Uint8List bytes,
    required String contentType,
  })
  onUploadVoiceReference;
  final GenerationHistoryRepository history;
  final HistoryPreviewLoader loadLibraryPreview;
  final PickedLibraryMediaReader readLibraryMedia;

  @override
  State<NarrationGenerationForm> createState() =>
      _NarrationGenerationFormState();
}

class _NarrationGenerationFormState extends State<NarrationGenerationForm> {
  final _text = TextEditingController();
  final _language = TextEditingController(text: 'English');
  final _seed = TextEditingController();
  String _voiceModel = 'chatterbox-turbo';
  XFile? _voiceReferenceFile;
  Uint8List? _voiceReferenceBytes;
  String? _voiceReferenceContentType;
  String? _voiceReferenceAssetId;
  bool _useVoiceClone = false;
  bool _voiceCloneConsent = false;
  bool _busy = false;
  String _busyLabel = 'Generate narration';

  @override
  void dispose() {
    _text.dispose();
    _language.dispose();
    _seed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              enabled: !_submitting,
              minLines: 6,
              maxLines: 12,
              maxLength: 6000,
              decoration: const InputDecoration(
                labelText: 'Narration text',
                hintText:
                    'Paste the script you want spoken. Keep it clean narration, not song lyrics.',
                alignLabelWithHint: true,
              ),
            ),
            if (widget.promptEnhance case final binding?)
              PromptEnhanceBar(
                controller: _text,
                binding: binding,
                enabled: !_submitting,
              ),
            IiOsGap.vSm,
            _NarrationOptions(
              submitting: _submitting,
              voiceModel: _voiceModel,
              language: _language,
              seed: _seed,
              onVoiceModelChanged: (value) =>
                  setState(() => _voiceModel = value ?? _voiceModel),
            ),
            IiOsGap.vSm,
            VoiceCloneReferenceField(
              enabled: !_submitting,
              useVoiceClone: _useVoiceClone,
              consent: _voiceCloneConsent,
              file: _voiceReferenceFile,
              contentType: _voiceReferenceContentType,
              onUseVoiceCloneChanged: (value) => setState(() {
                _useVoiceClone = value;
                if (!value) _voiceCloneConsent = false;
              }),
              onConsentChanged: _useVoiceClone
                  ? (value) => setState(() => _voiceCloneConsent = value)
                  : null,
              onSelect: _selectVoiceReference,
              onClear: _clearVoiceReference,
            ),
            IiOsGap.vXs,
            Text(
              'Narration is generated into your own workspace storage, and a '
              'voice sample you add is kept there too.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: IiOsPalette.of(context).muted,
              ),
            ),
            IiOsGap.vMd,
            _NarrationSubmitButton(
              enabled: widget.canSubmit && !_busy,
              submitting: _submitting,
              label: _busy
                  ? _busyLabel
                  : widget.submitting
                  ? 'Submitting narration generation\u2026'
                  : 'Generate narration',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  bool get _submitting => widget.submitting || _busy;

  Future<void> _selectVoiceReference() async {
    const audio = XTypeGroup(
      label: 'Audio',
      extensions: ['wav', 'mp3', 'm4a', 'aac'],
      mimeTypes: ['audio/wav', 'audio/mpeg', 'audio/mp4', 'audio/aac'],
    );
    final picked = await showMediaPicker(
      context: context,
      history: widget.history,
      loadPreview: widget.loadLibraryPreview,
      contentTypePrefix: 'audio/',
      title: 'Choose voice reference',
      uploadTypes: const [audio],
      maxUploadBytes: _maxVoiceReferenceBytes,
    );
    if (picked == null || !mounted) return;
    try {
      final selected = await readPickedMedia(
        picked,
        readLibrary: widget.readLibraryMedia,
      );
      final file = selected.file;
      final bytes = selected.bytes;
      if (bytes.length > _maxVoiceReferenceBytes) {
        throw const FormatException(
          'Voice reference audio must be 50 MB or smaller.',
        );
      }
      final contentType = sourceAudioContentType(bytes, filename: file.name);
      if (contentType == null) {
        throw const FormatException(
          'Use a WAV, MP3, M4A, or AAC voice reference.',
        );
      }
      if (!mounted) return;
      setState(() {
        _voiceReferenceFile = file;
        _voiceReferenceBytes = bytes;
        _voiceReferenceContentType = contentType;
        _voiceReferenceAssetId = null;
        _useVoiceClone = true;
      });
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  void _clearVoiceReference() {
    setState(() {
      _voiceReferenceFile = null;
      _voiceReferenceBytes = null;
      _voiceReferenceContentType = null;
      _voiceReferenceAssetId = null;
      _voiceCloneConsent = false;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_useVoiceClone) {
      await widget.onSubmit(
        text: _text.text,
        voiceModel: _voiceModel,
        language: _language.text,
        seed: _seed.text,
      );
      return;
    }
    if (!_voiceCloneConsent) {
      showFailure(
        context,
        const FormatException(
          'Confirm you have permission to use the reference voice.',
        ),
      );
      return;
    }
    if (_voiceReferenceFile == null ||
        _voiceReferenceBytes == null ||
        _voiceReferenceContentType == null) {
      showFailure(
        context,
        const FormatException('Select a voice reference audio file.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = _voiceReferenceAssetId == null
          ? 'Uploading voice reference\u2026'
          : 'Submitting narration generation\u2026';
    });
    try {
      final assetId = _voiceReferenceAssetId ?? await _uploadVoiceReference();
      if (mounted) {
        setState(() => _busyLabel = 'Submitting narration generation\u2026');
      }
      await widget.onSubmit(
        text: _text.text,
        voiceModel: _voiceModel,
        language: _language.text,
        seed: _seed.text,
        voiceReferenceAssetId: assetId,
        voiceCloneConsent: true,
      );
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = 'Generate narration';
        });
      }
    }
  }

  Future<String> _uploadVoiceReference() async {
    final assetId = await widget.onUploadVoiceReference(
      filename: _voiceReferenceFile!.name,
      bytes: _voiceReferenceBytes!,
      contentType: _voiceReferenceContentType!,
    );
    if (mounted) setState(() => _voiceReferenceAssetId = assetId);
    return assetId;
  }
}

class _NarrationOptions extends StatelessWidget {
  const _NarrationOptions({
    required this.submitting,
    required this.voiceModel,
    required this.language,
    required this.seed,
    required this.onVoiceModelChanged,
  });

  final bool submitting;
  final String voiceModel;
  final TextEditingController language;
  final TextEditingController seed;
  final ValueChanged<String?> onVoiceModelChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One voice ships, so this is a fact about the page rather than a
        // decision on it. A dropdown with a single item invites a choice that
        // does not exist, and still leaves the reader unsure what they get.
        _SpokenBy(voiceModel: voiceModel),
        IiOsGap.vSm,
        ResponsiveFieldPair(
          first: TextField(
            controller: language,
            enabled: !submitting,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Read in',
              hintText: 'English',
              helperText: 'A language name, such as English.',
            ),
          ),
          second: TextField(
            controller: seed,
            enabled: !submitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Seed (optional)',
              helperMaxLines: 2,
              helperText:
                  'Leave it blank for a fresh reading. Reuse the seed from a '
                  'result to get that one again.',
            ),
          ),
        ),
      ],
    );
  }
}

class _NarrationSubmitButton extends StatelessWidget {
  const _NarrationSubmitButton({
    required this.enabled,
    required this.submitting,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final bool submitting;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: submitting || !enabled ? null : onPressed,
        icon: submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.audioLines, size: 17),
        label: Text(label),
      ),
    );
  }
}

const _maxVoiceReferenceBytes = 50 * 1024 * 1024;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/character_design_regions.dart';
import '../widgets/character_designer.dart';
import '../widgets/character_essentials.dart';
import '../widgets/character_questionnaire.dart';
import '../widgets/common.dart';
import '../widgets/generated_media_surface.dart';

class CharacterBuilderScreen extends StatefulWidget {
  const CharacterBuilderScreen({
    required this.controller,
    required this.character,
    required this.onSaved,
    required this.onGenerated,
    required this.onClose,
    super.key,
  });

  final AppController controller;
  final CharacterModel character;
  final ValueChanged<CharacterModel> onSaved;
  final void Function(CharacterModel character, JsonMap job, bool body)
  onGenerated;
  final VoidCallback onClose;

  @override
  State<CharacterBuilderScreen> createState() => _CharacterBuilderScreenState();
}

class _CharacterBuilderScreenState extends State<CharacterBuilderScreen> {
  late CharacterModel _character = widget.character;
  late final TextEditingController _name = TextEditingController(
    text: widget.character.name == 'Untitled character'
        ? ''
        : widget.character.name,
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
  Timer? _debounce;
  bool _saving = false;
  bool _generating = false;
  bool _dirty = false;
  int _revision = 0;
  String? _saveError;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
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
    return PageFrame(
      title: 'Character builder',
      subtitle:
          'Build one full-body sheet · all details are optional · autosaves as you type',
      actions: [
        TextButton.icon(
          onPressed: _saving || _generating ? null : _close,
          icon: const Icon(LucideIcons.arrowLeft, size: 17),
          label: const Text('Characters'),
        ),
      ],
      stickyFooter: _CharacterGenerationFooter(
        label: 'Generate full-body sheet',
        enabled: _hasCurrentPrompt && _canGenerate && !_saving && !_generating,
        busy: _generating,
        onPressed: _generate,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The sheet preview area. It has to exist before the artifact does,
          // because every asynchronous generation must show its loading state
          // where the generated sheet will land -- not only on the button that
          // started the job.
          if (_generating) ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(IiOsSpacing.md),
                child: GeneratedMediaLoadingSurface(
                  kind: GeneratedMediaKind.image,
                  label: 'Generating full-body sheet\u2026',
                ),
              ),
            ),
            IiOsGap.vMd,
          ],
          CharacterEssentials(
            name: _name,
            answers: _answers,
            onChanged: _changed,
            enabled: _character.isDraft && !_generating,
          ),
          IiOsGap.vMd,
          const _BodyTextToImageNotice(),
          IiOsGap.vMd,
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
                    enabled: _character.isDraft && !_generating,
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
        ],
      ),
    );
  }

  bool get _hasCurrentPrompt => _character.bodyPrompt.trim().isNotEmpty;

  String _promptDetails(String prompt) => prompt
      .replaceFirst(RegExp(r'^TEXT-TO-IMAGE FULL-BODY CHARACTER SHEET\s*'), '')
      .trim();

  bool get _canGenerate => widget.controller.can('jobs.trigger');

  void _changed() {
    if (!_character.isDraft) return;
    _debounce?.cancel();
    setState(() {
      _dirty = true;
      _revision++;
      _saveError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 650), _save);
  }

  Future<bool> _save() async {
    _debounce?.cancel();
    if (!_character.isDraft) return true;
    if (_saving || !_dirty) return !_saving;
    final savingRevision = _revision;
    setState(() => _saving = true);
    try {
      final response = await widget.controller.api.patch(
        _characterPath,
        body: _payload(),
      );
      final saved = CharacterModel.fromJson(asJsonMap(response['data']));
      if (!mounted) return true;
      setState(() {
        _character = saved;
        _dirty = _revision != savingRevision;
        _saveError = null;
      });
      widget.onSaved(saved);
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_dirty && _saveError == null) {
          _debounce = Timer(Duration.zero, _save);
        }
      }
    }
  }

  Future<void> _close() async {
    final saved = await _save();
    if (saved && mounted) widget.onClose();
  }

  Future<void> _generate() async {
    if (!_hasCurrentPrompt || !_canGenerate) return;
    _debounce?.cancel();
    setState(() {
      _generating = true;
      _saveError = null;
    });
    try {
      var saved = _character;
      if (saved.isDraft) {
        final response = await widget.controller.api.patch(
          _characterPath,
          body: {..._payload(), 'status': 'ready'},
        );
        saved = CharacterModel.fromJson(asJsonMap(response['data']));
        if (!mounted) return;
        setState(() {
          _character = saved;
          _dirty = false;
        });
      }
      final generation = await widget.controller.api.post(
        '$_characterPath/generate-body',
      );
      final data = asJsonMap(generation['data']);
      final generated = CharacterModel.fromJson(asJsonMap(data['character']));
      final job = asJsonMap(data['job']);
      if (!mounted) return;
      unawaited(widget.controller.refreshDashboard());
      widget.onGenerated(generated, job, true);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  JsonMap _payload() => {
    'name': _name.text.trim().isEmpty
        ? 'Untitled character'
        : _name.text.trim(),
    'answers': {
      for (final entry in _answers.entries) entry.key: entry.value.text.trim(),
    },
    'bodyAnswers': {
      for (final entry in _bodyAnswers.entries)
        entry.key: entry.value.text.trim(),
    },
    'clothingAnswers': {
      for (final entry in _clothingAnswers.entries)
        entry.key: entry.value.text.trim(),
    },
  };

  String get _characterPath =>
      'v1/workspaces/${widget.controller.workspace!.id}/characters/${_character.id}';
}

class _CharacterGenerationFooter extends StatelessWidget {
  const _CharacterGenerationFooter({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        return Material(
          elevation: 8,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(IiOsRadii.pill),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: IiOsColors.border),
              borderRadius: BorderRadius.circular(IiOsRadii.pill),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(IiOsSpacing.xs),
              child: FilledButton.icon(
                onPressed: enabled ? onPressed : null,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.sparkles, size: 17),
                label: Text(compact ? 'Generate' : label),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BodyTextToImageNotice extends StatelessWidget {
  const _BodyTextToImageNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Row(
          children: [
            const Icon(LucideIcons.info, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Body generation is a separate text-to-image job. It carries the complete head description into one full-body character sheet using the body and clothing details below.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

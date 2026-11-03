import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/character.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'character_design_regions.dart';
import 'character_silhouette.dart';
import 'common.dart';

class CharacterDesigner extends StatefulWidget {
  const CharacterDesigner({
    required this.kind,
    required this.headAnswers,
    required this.bodyAnswers,
    required this.clothingAnswers,
    required this.onChanged,
    required this.enabled,
    super.key,
  });

  final CharacterDesignKind kind;
  final Map<String, TextEditingController> headAnswers;
  final Map<String, TextEditingController> bodyAnswers;
  final Map<String, TextEditingController> clothingAnswers;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  State<CharacterDesigner> createState() => _CharacterDesignerState();
}

class _CharacterDesignerState extends State<CharacterDesigner> {
  late String _selectedRegionId = _defaultRegionId(widget.kind);

  @override
  void didUpdateWidget(covariant CharacterDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _selectedRegionId = _defaultRegionId(widget.kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHead = widget.kind == CharacterDesignKind.head;
    final isCombined = widget.kind == CharacterDesignKind.combined;
    final regions = isHead
        ? headDesignRegions
        : isCombined
        ? combinedDesignRegions
        : bodyDesignRegions;
    final controllers = isHead
        ? {
            for (final question in characterHeadQuestions)
              question.key: widget.headAnswers[question.key]!,
          }
        : isCombined
        ? {
            ...widget.headAnswers,
            ...widget.bodyAnswers,
            ...widget.clothingAnswers,
          }
        : {...widget.bodyAnswers, ...widget.clothingAnswers};
    final questions = isHead
        ? characterHeadQuestions
        : isCombined
        ? [
            ...characterHeadQuestions,
            ...characterBodyQuestions,
            ...characterClothingQuestions,
          ]
        : [...characterBodyQuestions, ...characterClothingQuestions];
    final questionByKey = {
      for (final question in questions) question.key: question,
    };
    final completion = {
      for (final region in regions) region.id: _completion(region, controllers),
    };
    final selected = regions.firstWhere(
      (region) => region.id == _selectedRegionId,
      orElse: () => regions.first,
    );
    final answered = controllers.values
        .where((controller) => controller.text.trim().isNotEmpty)
        .length;
    final total = controllers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(
                  isHead
                      ? 'Shape the head'
                      : isCombined
                      ? 'Shape the character'
                      : 'Shape the full body',
                  trailing: Text(
                    '$answered of $total details',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isHead
                      ? 'Choose a feature on the silhouette or in the menu, then describe it in your own words. Grey areas gain color as you define them.'
                      : 'Choose a body or clothing area, then describe the exact proportions and construction to preserve. Grey areas gain color as you define them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IiOsGap.vSm,
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    key: ValueKey('character-${widget.kind.name}-progress'),
                    value: total == 0 ? 0 : answered / total,
                    minHeight: 7,
                    backgroundColor: IiOsColors.border,
                  ),
                ),
                IiOsGap.vMd,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final region in regions)
                      _RegionChip(
                        region: region,
                        selected: selected.id == region.id,
                        completion: completion[region.id] ?? 0,
                        onSelected: () =>
                            setState(() => _selectedRegionId = region.id),
                      ),
                  ],
                ),
                IiOsGap.vLg,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final silhouette = SizedBox(
                      height: isHead ? 360 : 460,
                      child: CharacterSilhouette(
                        kind: widget.kind,
                        regions: regions,
                        selectedRegionId: selected.id,
                        completion: completion,
                        onRegionSelected: (id) =>
                            setState(() => _selectedRegionId = id),
                      ),
                    );
                    final editor = _RegionEditor(
                      region: selected,
                      questionByKey: questionByKey,
                      controllers: controllers,
                      onChanged: widget.onChanged,
                      enabled: widget.enabled,
                    );
                    if (constraints.maxWidth < 760) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [silhouette, IiOsGap.vMd, editor],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 300, child: silhouette),
                        IiOsGap.hLg,
                        Expanded(child: editor),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _defaultRegionId(CharacterDesignKind kind) =>
      kind == CharacterDesignKind.head || kind == CharacterDesignKind.combined
      ? 'face'
      : 'silhouette';

  static double _completion(
    CharacterDesignRegion region,
    Map<String, TextEditingController> controllers,
  ) {
    final answered = region.questionKeys
        .where((key) => controllers[key]?.text.trim().isNotEmpty == true)
        .length;
    return region.questionKeys.isEmpty
        ? 0
        : answered / region.questionKeys.length;
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.region,
    required this.selected,
    required this.completion,
    required this.onSelected,
  });

  final CharacterDesignRegion region;
  final bool selected;
  final double completion;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final complete = completion >= 1;
    final count = (completion * region.questionKeys.length).round();
    return ChoiceChip(
      key: ValueKey('character-region-${region.id}'),
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: Icon(
        complete ? LucideIcons.circleCheck : region.icon,
        size: 16,
        color: complete ? IiOsColors.green : null,
      ),
      label: Text(
        '${region.label} · $count/${region.questionKeys.length}',
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: region.description,
    );
  }
}

class _RegionEditor extends StatelessWidget {
  const _RegionEditor({
    required this.region,
    required this.questionByKey,
    required this.controllers,
    required this.onChanged,
    required this.enabled,
  });

  final CharacterDesignRegion region;
  final Map<String, CharacterQuestion> questionByKey;
  final Map<String, TextEditingController> controllers;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final questions = region.questionKeys
        .map((key) => questionByKey[key])
        .whereType<CharacterQuestion>()
        .toList();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey('character-region-editor-${region.id}'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: IiOsColors.canvas,
          border: Border.all(color: IiOsColors.border),
          borderRadius: BorderRadius.circular(IiOsRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(region.icon, size: 20, color: IiOsColors.green),
                IiOsGap.hXs,
                Expanded(
                  child: Text(
                    region.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            IiOsGap.vXxs,
            Text(
              region.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            for (var index = 0; index < questions.length; index++) ...[
              _GuidedQuestionField(
                question: questions[index],
                controller: controllers[questions[index].key]!,
                onChanged: onChanged,
                enabled: enabled,
              ),
              if (index < questions.length - 1) IiOsGap.vMd,
            ],
          ],
        ),
      ),
    );
  }
}

class _GuidedQuestionField extends StatelessWidget {
  const _GuidedQuestionField({
    required this.question,
    required this.controller,
    required this.onChanged,
    required this.enabled,
  });

  final CharacterQuestion question;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(question.question, style: Theme.of(context).textTheme.titleMedium),
        if (question.guidance != null) ...[
          IiOsGap.vXxs,
          Text(
            question.guidance!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        IiOsGap.vXs,
        TextField(
          key: ValueKey('character-field-${question.key}'),
          controller: controller,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          minLines: 3,
          maxLines: 6,
          maxLength: 1200,
          decoration: InputDecoration(
            hintText: question.example,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

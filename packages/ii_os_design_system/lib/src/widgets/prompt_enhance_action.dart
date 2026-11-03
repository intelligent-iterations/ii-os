import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/palette.dart';
import '../tokens/icons.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

part 'prompt_enhance_action_button.dart';

/// What happened the last time this field was offered to the rewriter.
enum PromptEnhanceOutcome {
  /// Nothing has been asked for yet.
  idle,

  /// A rewrite is in flight.
  running,

  /// The field now holds a rewrite, and the original is one tap away.
  rewritten,

  /// No rewrite happened and the text is exactly as it was typed.
  unchanged,
}

/// Offers to rewrite one creative field against its own model's prompting
/// guide, and says plainly what came back.
///
/// Sits under the field it acts on rather than inside it: the result replaces
/// what the person wrote, so the control that did it and the sentence
/// explaining what it did belong where they can see both at once. [onUndo]
/// restores the original text, which is what makes replacing it in place fair
/// -- nothing is lost by trying.
///
/// Pass a null [onEnhance] to disable the action, and a [message] saying why
/// and how to get unblocked. An action that looks available and then refuses is
/// worse than one that explains itself up front.
class PromptEnhanceAction extends StatelessWidget {
  const PromptEnhanceAction({
    required this.outcome,
    required this.onEnhance,
    required this.tooltip,
    this.onUndo,
    this.onOpenGuide,
    this.message,
    this.label = 'Enhance',
    super.key,
  });

  final PromptEnhanceOutcome outcome;

  /// Null disables the action. Pair it with a [message] naming the reason.
  final VoidCallback? onEnhance;

  /// Restores the text as it was before the rewrite.
  final VoidCallback? onUndo;

  /// Opens the model author's prompting guidance, when one is known.
  final VoidCallback? onOpenGuide;

  /// One sentence about the last attempt, or about why the action is off.
  final String? message;

  /// What the button says. The tooltip carries the detail.
  final String label;
  final String tooltip;

  bool get _busy => outcome == PromptEnhanceOutcome.running;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final note = message;
    return Padding(
      padding: const EdgeInsets.only(top: IiOsSpacing.xs),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: IiOsSpacing.xs,
        runSpacing: IiOsSpacing.xxs,
        children: [
          Tooltip(
            message: tooltip,
            child: _PromptEnhanceButton(
              busy: _busy,
              label: label,
              onPressed: onEnhance,
            ),
          ),
          if (onUndo != null && !_busy)
            Tooltip(
              message: 'Put back the text you wrote',
              child: TextButton.icon(
                onPressed: onUndo,
                icon: const Icon(LucideIcons.undo2, size: IiOsIconSize.sm),
                label: const Text('Undo'),
              ),
            ),
          if (onOpenGuide != null)
            TextButton.icon(
              onPressed: onOpenGuide,
              icon: const Icon(LucideIcons.externalLink, size: IiOsIconSize.sm),
              label: const Text('Official guide'),
            ),
          if (note != null)
            Semantics(
              liveRegion: true,
              child: Text(
                note,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: outcome == PromptEnhanceOutcome.unchanged
                      ? palette.warning.text
                      : palette.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

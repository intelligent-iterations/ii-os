import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:url_launcher/url_launcher.dart';

/// Everything one creative field needs to offer a rewrite.
///
/// Bundled so a form that already takes a dozen parameters gains one rather
/// than six, and so every creative surface offers the affordance the same way
/// instead of each assembling its own.
final class PromptEnhanceBinding {
  const PromptEnhanceBinding({
    required this.outcome,
    required this.tooltip,
    required this.onEnhance,
    required this.onUndo,
    this.message,
    this.canUndo = false,
    this.guideSource,
  });

  final PromptEnhanceOutcome outcome;
  final String tooltip;
  final String? message;
  final bool canUndo;

  /// First-party prompting guidance for the selected model, when known.
  final Uri? guideSource;

  /// Rewrites the given text, returning the replacement or null if unchanged.
  final Future<String?> Function(String current) onEnhance;

  /// Returns the text as it was before the rewrite, or null.
  final String? Function() onUndo;
}

/// The enhance affordance for one text field, placed directly beneath it.
///
/// Owns the swap between the field's text and the rewrite so no call site has
/// to: every creative surface passes its controller and its binding, and the
/// behaviour -- including putting the original back -- is identical everywhere.
///
/// Listens to the controller so the action switches off the moment the field is
/// empty. There is nothing to rewrite then, and a button that is live over an
/// empty box invites a round trip that can only fail.
class PromptEnhanceBar extends StatelessWidget {
  const PromptEnhanceBar({
    required this.controller,
    required this.binding,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final PromptEnhanceBinding binding;
  final bool enabled;

  Future<void> _enhance() async {
    final replacement = await binding.onEnhance(controller.text);
    if (replacement != null) controller.text = replacement;
  }

  void _undo() {
    final original = binding.onUndo();
    if (original != null) controller.text = original;
  }

  Future<void> _openGuide(BuildContext context) async {
    final source = binding.guideSource;
    if (source == null) return;
    final opened = await launchUrl(source, webOnlyWindowName: '_blank');
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open the official guide.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => PromptEnhanceAction(
        outcome: binding.outcome,
        message: binding.message,
        tooltip: binding.tooltip,
        onEnhance: enabled && value.text.trim().isNotEmpty ? _enhance : null,
        onUndo: binding.canUndo ? _undo : null,
        onOpenGuide: binding.guideSource == null
            ? null
            : () => _openGuide(context),
      ),
    );
  }
}

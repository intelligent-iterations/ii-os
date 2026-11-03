import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/spacing.dart';

/// A generation form beside its live preview, once there is room for both.
///
/// Every generation screen used to plant its form alone on the page and only
/// insert the result *below* it once a job existed, so the page grew and
/// re-flowed on every submit. This reserves the preview's place from first
/// paint instead -- [preview] is expected to already fill a fixed-shape slot
/// itself (a `GenerationSlot` or the real result widget), so switching
/// between idle, working, and arrived repaints in place rather than pushing
/// the form down the page.
///
/// Narrow windows keep today's behavior: the form first, then the preview
/// below it, so nothing regresses on a phone. Its direct sibling in spirit is
/// [ResponsiveFieldPair] -- same shape, one level up: a pane and its preview
/// rather than two fields.
class GenerationWorkspace extends StatelessWidget {
  const GenerationWorkspace({
    required this.form,
    required this.preview,
    super.key,
  });

  /// The prompt, options, and submit control for this generation kind.
  final Widget form;

  /// The output region -- an idle hint, a working animation, or the arrived
  /// result -- occupying the same reserved place in every phase.
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < IiOsBreakpoints.sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [form, IiOsGap.vMd, preview],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: _formPaneWidth, child: form),
            IiOsGap.hXl,
            Expanded(child: preview),
          ],
        );
      },
    );
  }
}

/// Matches the felt width of the single centred form Card these screens used
/// before the preview pane existed.
const _formPaneWidth = 480.0;

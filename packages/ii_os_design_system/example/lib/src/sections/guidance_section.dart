import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../widgets/spec_panel.dart';

class GuidanceSection extends StatelessWidget {
  const GuidanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SpecPanel(
      title: 'PromptingGuideButton',
      caption:
          'Model-specific advice opens beside the field where it is needed. '
          'The component takes plain copy and callbacks so video, image, and '
          'audio tools can each provide their own official guidance.',
      children: [
        PromptingGuideButton(
          title: 'Write a stronger video prompt',
          summary: 'Plan a short timeline instead of listing keywords.',
          sections: const [
            PromptingGuideSection(
              title: 'Stage the action',
              body: 'Say what changes from the opening to the final frame.',
            ),
            PromptingGuideSection(
              title: 'Direct the camera',
              body: 'Name the framing, motion, range, and speed that matter.',
            ),
          ],
          promptTemplate: '[Shot 1] Subject, action, camera, and sound\u2026',
          onOpenSource: () async {},
        ),
        IiOsGap.vXl,
        const SpecPanel(
          title: 'PromptEnhanceAction',
          caption:
              'The same guidance, applied rather than read. Every state is '
              'shown because the sentence beside the button is the whole '
              'point: a rewrite the person can undo, and a refusal that says '
              'what to do about it.',
          children: [
            PromptEnhanceAction(
              outcome: PromptEnhanceOutcome.idle,
              onEnhance: _noop,
              onOpenGuide: _noop,
              tooltip: 'Rewrite this against the prompting guide for LTX 2.3',
            ),
            PromptEnhanceAction(
              outcome: PromptEnhanceOutcome.running,
              onEnhance: _noop,
              tooltip: 'Rewrite this against the prompting guide for LTX 2.3',
            ),
            PromptEnhanceAction(
              outcome: PromptEnhanceOutcome.rewritten,
              onEnhance: _noop,
              onUndo: _noop,
              message: 'Rewritten for LTX 2.3.',
              tooltip: 'Rewrite this against the prompting guide for LTX 2.3',
            ),
            PromptEnhanceAction(
              outcome: PromptEnhanceOutcome.unchanged,
              onEnhance: _noop,
              message:
                  'Your text is unchanged. DeepSeek did not answer. Try again '
                  'in a moment.',
              tooltip: 'Rewrite this against the prompting guide for LTX 2.3',
            ),
          ],
        ),
        IiOsGap.vXl,
        const SpecPanel(
          title: 'Guide content, unwrapped',
          caption:
              'What the button opens. Shown on its own because a sheet is not '
              'a place anyone reviews spacing or type.',
          children: [
            PromptingGuideContent(
              summary: 'Describe the subject before the style.',
              sections: [
                PromptingGuideSection(
                  title: 'Name the subject',
                  body: 'Who or what is in frame, and what they are doing.',
                ),
                PromptingGuideSection(
                  title: 'Then the treatment',
                  body: 'Lens, light, and grade come after the subject.',
                ),
              ],
              promptTemplate: 'A <subject> <action>, <lens>, <light>\u2026',
            ),
          ],
        ),
      ],
    );
  }
}

void _noop() {}

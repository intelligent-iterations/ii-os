import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'storyboard_editor_components.dart';
import 'storyboard_reference_selector.dart';

List<StoryboardPanelReferenceOption> storyboardPanelReferenceOptions({
  required List<StoryboardPanelDraft> panels,
  required AppController controller,
  required String workspaceId,
}) => [
  for (final (index, panel) in panels.indexed)
    if (panel.imageArtifact case final artifact?)
      if (panel.imageJobId case final jobId?)
        StoryboardPanelReferenceOption(
          id: panel.id,
          name: 'Panel ${index + 1}',
          description: panel.prompt.text.trim().isEmpty
              ? 'Panel ${index + 1}'
              : panel.prompt.text.trim(),
          thumbnail: ClipOval(
            child: SizedBox.square(
              dimension: 22,
              child: StoryboardArtifactImage(
                key: ValueKey(
                  'storyboard-reference-thumbnail-${panel.id}-$jobId-'
                  '${artifact['path']}-${artifact['generation']}',
                ),
                controller: controller,
                workspaceId: workspaceId,
                jobId: jobId,
                artifact: artifact,
              ),
            ),
          ),
        ),
];

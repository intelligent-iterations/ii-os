import 'package:flutter/material.dart';

import '../theme/ii_os_tokens.dart';

final class VideoEditorProgressSurface extends StatelessWidget {
  const VideoEditorProgressSurface({
    required this.stage,
    required this.progress,
    required this.onCancel,
    super.key,
  });

  final String stage;
  final double? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('video-editor-output-surface'),
    color: Colors.black,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: progress),
            IiOsGap.vMd,
            Text(
              stage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (onCancel != null) ...[
              IiOsGap.vSm,
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Cancel local render'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

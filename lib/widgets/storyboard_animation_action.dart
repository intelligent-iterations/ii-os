import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class StoryboardAnimationAction extends StatelessWidget {
  const StoryboardAnimationAction({
    required this.hasVideo,
    required this.isAnimating,
    required this.canAnimate,
    required this.onAnimate,
    this.compact = false,
    super.key,
  });

  final bool hasVideo;
  final bool isAnimating;
  final bool canAnimate;
  final VoidCallback onAnimate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fullLabel = hasVideo ? 'Open animation' : 'Animate panel';
    final label = compact ? (hasVideo ? 'Open' : 'Animate') : fullLabel;
    return Tooltip(
      message: canAnimate || hasVideo
          ? fullLabel
          : 'Generate the panel image first',
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        ),
        onPressed: canAnimate || hasVideo ? onAnimate : null,
        icon: isAnimating
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                hasVideo ? LucideIcons.circlePlay : LucideIcons.clapperboard,
                size: 17,
              ),
        label: Text(label, maxLines: 1, overflow: TextOverflow.fade),
      ),
    );
  }
}

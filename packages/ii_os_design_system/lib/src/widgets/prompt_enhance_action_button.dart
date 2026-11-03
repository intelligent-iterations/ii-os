part of 'prompt_enhance_action.dart';

/// The luminous, local-only action state shown while a rewrite is in flight.
class _PromptEnhanceButton extends StatelessWidget {
  const _PromptEnhanceButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return AnimatedContainer(
      key: busy ? const ValueKey('prompt-enhance-glow') : null,
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: IiOsRadii.pillAll,
        boxShadow: busy
            ? [
                BoxShadow(
                  color: palette.accent.fill.withValues(alpha: 0.38),
                  blurRadius: IiOsSpacing.lg,
                ),
              ]
            : const [],
      ),
      child: Stack(
        children: [
          if (busy)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('prompt-enhance-overlay'),
                  decoration: BoxDecoration(
                    borderRadius: IiOsRadii.pillAll,
                    gradient: LinearGradient(
                      colors: [
                        palette.info.container,
                        palette.accent.container,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: busy ? null : onPressed,
            style: busy
                ? TextButton.styleFrom(
                    disabledForegroundColor: palette.accent.text,
                  )
                : null,
            icon: busy
                ? SizedBox.square(
                    dimension: IiOsIconSize.sm,
                    child: CircularProgressIndicator(
                      color: palette.accent.text,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(LucideIcons.sparkles, size: IiOsIconSize.sm),
            label: Text(busy ? 'Enhancing\u2026' : label),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/elevation.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// What the output region is currently doing.
enum GenerationPhase { idle, working, arrived, failed }

/// The region a generated artifact will appear in, in every state it can hold.
///
/// ii-os requires that clicking a generation command immediately shows
/// progress *in the surface where the output will land*, from dispatch until a
/// terminal state -- never a disabled button and an idle empty region. That rule
/// had no component to satisfy it, so each screen either improvised or skipped
/// it.
///
/// The states are one widget rather than four because the contract is about
/// continuity: the placeholder, the spinner, the artifact, and the failure all
/// have to occupy the same box, or the eye loses the thing it was told to
/// watch. Swapping between separately-authored widgets is how a layout jumps
/// at the exact moment a person is waiting on it.
///
/// This is also the one surface in ii-os where movement is the point. A render
/// finishing is the payoff of the whole product, so [GenerationPhase.arrived]
/// is allowed a small overshoot. Failure is not: it fades, because a console
/// that bounces while telling you it lost your job is a console you stop
/// believing.
class GenerationSlot extends StatelessWidget {
  const GenerationSlot({
    required this.phase,
    this.child,
    this.idleHint = 'Your result will appear here',
    this.workingLabel = 'Generating',
    this.failureMessage = 'That generation did not finish.',
    this.onRetry,
    this.aspectRatio = 1,
    super.key,
  });

  /// Which state to render.
  final GenerationPhase phase;

  /// The finished artifact. Shown only in [GenerationPhase.arrived].
  final Widget? child;

  final String idleHint;
  final String workingLabel;
  final String failureMessage;

  /// Recovery for [GenerationPhase.failed], offered in the same surface.
  final VoidCallback? onRetry;

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: phase == GenerationPhase.working,
      label: switch (phase) {
        GenerationPhase.idle => idleHint,
        GenerationPhase.working => workingLabel,
        GenerationPhase.arrived => 'Generation complete',
        GenerationPhase.failed => failureMessage,
      },
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: AnimatedContainer(
          duration: IiOsMotion.of(context, IiOsMotion.base),
          curve: IiOsMotion.standard,
          decoration: BoxDecoration(
            color: switch (phase) {
              GenerationPhase.failed => IiOsColors.redTint,
              GenerationPhase.arrived => IiOsColors.surface,
              _ => IiOsColors.neutralTint,
            },
            borderRadius: IiOsRadii.lgAll,
            border: Border.all(
              color: switch (phase) {
                GenerationPhase.failed => IiOsColors.red,
                GenerationPhase.working => IiOsColors.green,
                _ => IiOsColors.border,
              },
            ),
            boxShadow: switch (phase) {
              GenerationPhase.working => IiOsElevation.working,
              GenerationPhase.arrived => IiOsElevation.low,
              _ => null,
            },
          ),
          clipBehavior: Clip.antiAlias,
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return switch (phase) {
      GenerationPhase.idle => _Centred(
        icon: Icons.image_outlined,
        label: idleHint,
        tone: IiOsColors.muted,
      ),
      GenerationPhase.working => _Working(label: workingLabel),
      GenerationPhase.arrived => _Arrived(child: child ?? const SizedBox()),
      GenerationPhase.failed => _Failure(
        message: failureMessage,
        onRetry: onRetry,
      ),
    };
  }
}

class _Centred extends StatelessWidget {
  const _Centred({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: tone),
            IiOsGap.vXs,
            ExcludeSemantics(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slow sweep across the placeholder while the workflow runs.
///
/// The sweep is decorative, so it is suppressed outright under reduced motion
/// rather than merely shortened -- a looping highlight still pulls the eye at
/// any speed. The label and the determinate-free progress bar carry the state
/// on their own when it is off.
class _Working extends StatefulWidget {
  const _Working({required this.label});

  final String label;

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (IiOsMotion.decorativeAllowed(context)) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (IiOsMotion.decorativeAllowed(context))
          AnimatedBuilder(
            key: const ValueKey('generation-sweep'),
            animation: _sweep,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.6 + _sweep.value * 3.2, -1),
                  end: Alignment(-0.6 + _sweep.value * 3.2, 1),
                  colors: const [
                    IiOsColors.neutralTint,
                    IiOsColors.greenTint,
                    IiOsColors.neutralTint,
                  ],
                ),
              ),
            ),
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: IiOsColors.green,
                  ),
                ),
                IiOsGap.vSm,
                ExcludeSemantics(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: IiOsColors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The artifact taking its place, with a small overshoot.
class _Arrived extends StatelessWidget {
  const _Arrived({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = IiOsMotion.of(context, IiOsMotion.arrival);
    return TweenAnimationBuilder<double>(
      key: const ValueKey('generation-arrived'),
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: IiOsMotion.arrive,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.scale(scale: 0.96 + 0.04 * value, child: child),
      ),
      child: child,
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 26, color: IiOsColors.red),
            IiOsGap.vXs,
            ExcludeSemantics(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: IiOsColors.red),
              ),
            ),
            if (onRetry != null) ...[
              IiOsGap.vSm,
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// The ii-os brand mark.
///
/// Drawn rather than shipped as an asset so it stays crisp at every size and
/// carries no image decode on first paint -- it is the first thing rendered.
/// The numbers inside [_IiOsMarkPainter] are artwork geometry on a 64pt grid,
/// not layout tokens, which is why they are literals.
class IiOsMark extends StatelessWidget {
  const IiOsMark({this.size = 40, this.semanticLabel, super.key});

  final double size;

  /// Announced to screen readers. Null makes the mark decorative, which is
  /// correct when a visible "ii-os" wordmark sits beside it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _IiOsMarkPainter()),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: mark,
    );
  }
}

/// The screen shown while the session is restored, before the app can decide
/// whether to route to sign-in or a workspace.
class IiOsStartupView extends StatelessWidget {
  const IiOsStartupView({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Opening your ii-os workspace',
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IiOsMark(size: 64),
              IiOsGap.vMd,
              Text('ii-os', style: text.displaySmall),
              IiOsGap.vXs,
              Text('Creative operations, in motion.', style: text.bodySmall),
              IiOsGap.vXxl,
              const SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: IiOsColors.green,
                  backgroundColor: IiOsColors.border,
                  borderRadius: IiOsRadii.pillAll,
                ),
              ),
              IiOsGap.vSm,
              Text('Restoring your session\u2026', style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _IiOsMarkPainter extends CustomPainter {
  const _IiOsMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 64;
    canvas.save();
    canvas.scale(scale, scale);

    final background = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2, 2, 60, 60),
      const Radius.circular(15),
    );
    canvas.drawRRect(background, Paint()..color = IiOsColors.ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.5, 2.5, 59, 59),
        const Radius.circular(14.5),
      ),
      Paint()
        ..color = const Color(0xFF2F3938)
        ..style = PaintingStyle.stroke,
    );

    final green = Paint()..color = const Color(0xFF5ED6B2);
    final white = Paint()..color = IiOsColors.canvas;
    canvas.drawCircle(const Offset(24, 20), 4.5, green);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(19.5, 28, 9, 20),
        const Radius.circular(4.5),
      ),
      green,
    );
    canvas.drawCircle(const Offset(40, 20), 4.5, white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(35.5, 28, 9, 20),
        const Radius.circular(4.5),
      ),
      white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IiOsMarkPainter oldDelegate) => false;
}

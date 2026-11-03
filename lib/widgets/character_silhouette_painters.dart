part of 'character_silhouette.dart';

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({
    required this.kind,
    required this.selectedRegionId,
    required this.completion,
  });

  final CharacterDesignKind kind;
  final String selectedRegionId;
  final Map<String, double> completion;

  Color _fill(String id) {
    final amount = completion[id] ?? 0;
    if (selectedRegionId == id && amount > 0) {
      return IiOsColors.green.withValues(alpha: 0.36);
    }
    if (amount >= 1) return IiOsColors.green.withValues(alpha: 0.3);
    if (amount > 0) return IiOsColors.blue.withValues(alpha: 0.2);
    return IiOsColors.muted.withValues(alpha: 0.13);
  }

  Color _fillGroup(List<String> ids) {
    final amount =
        ids.fold<double>(0, (total, id) => total + (completion[id] ?? 0)) /
        ids.length;
    if (ids.contains(selectedRegionId) && amount > 0) {
      return IiOsColors.green.withValues(alpha: 0.36);
    }
    if (amount >= 0.999) return IiOsColors.green.withValues(alpha: 0.3);
    if (amount > 0) return IiOsColors.blue.withValues(alpha: 0.2);
    return IiOsColors.muted.withValues(alpha: 0.13);
  }

  Paint _groupPaint(
    List<String> ids, {
    PaintingStyle style = PaintingStyle.fill,
  }) => Paint()
    ..color = style == PaintingStyle.fill ? _fillGroup(ids) : IiOsColors.muted
    ..style = style
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  Paint _paint(String id, {PaintingStyle style = PaintingStyle.fill}) => Paint()
    ..color = style == PaintingStyle.fill ? _fill(id) : IiOsColors.muted
    ..style = style
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (kind == CharacterDesignKind.head) {
      _paintHead(canvas, size);
    } else {
      _paintBody(canvas, size);
    }
  }

  void _paintHead(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.45);
    final face = Rect.fromCenter(
      center: c,
      width: size.width * 0.48,
      height: size.height * 0.53,
    );
    const faceRegions = ['direction', 'identity', 'face', 'details'];
    canvas.drawOval(face, _groupPaint(faceRegions));
    canvas.drawOval(face, _paint('face', style: PaintingStyle.stroke));
    canvas.drawOval(
      Rect.fromLTWH(
        face.left - size.width * 0.035,
        face.top + face.height * 0.36,
        size.width * 0.07,
        face.height * 0.2,
      ),
      _paint('ears'),
    );
    canvas.drawOval(
      Rect.fromLTWH(
        face.right - size.width * 0.035,
        face.top + face.height * 0.36,
        size.width * 0.07,
        face.height * 0.2,
      ),
      _paint('ears'),
    );
    canvas.drawArc(
      face.deflate(4),
      3.35,
      2.85,
      false,
      _paint('hair', style: PaintingStyle.stroke)..strokeWidth = 24,
    );
    final eyeY = face.top + face.height * 0.43;
    canvas.drawLine(
      Offset(face.left + face.width * 0.23, eyeY),
      Offset(face.left + face.width * 0.43, eyeY),
      _paint('eyes')..strokeWidth = 8,
    );
    canvas.drawLine(
      Offset(face.left + face.width * 0.57, eyeY),
      Offset(face.left + face.width * 0.77, eyeY),
      _paint('eyes')..strokeWidth = 8,
    );
    canvas.drawLine(
      Offset(c.dx, eyeY + 8),
      Offset(c.dx - 4, face.top + face.height * 0.65),
      _paint('nose')..strokeWidth = 7,
    );
    canvas.drawLine(
      Offset(c.dx - face.width * 0.11, face.top + face.height * 0.76),
      Offset(c.dx + face.width * 0.11, face.top + face.height * 0.76),
      _paint('mouth')..strokeWidth = 8,
    );
    final neck = Rect.fromCenter(
      center: Offset(c.dx, face.bottom + size.height * 0.04),
      width: size.width * 0.17,
      height: size.height * 0.15,
    );
    canvas.drawRect(neck, _paint('headClothing'));
    final shoulders = Path()
      ..moveTo(size.width * 0.12, size.height)
      ..quadraticBezierTo(
        c.dx,
        size.height * 0.72,
        size.width * 0.88,
        size.height,
      )
      ..close();
    canvas.drawPath(shoulders, _paint('headClothing'));
  }

  void _paintBody(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, size.height * 0.12),
        width: size.width * 0.24,
        height: size.height * 0.17,
      ),
      _groupPaint(['silhouette', 'back']),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height * 0.34),
          width: size.width * 0.3,
          height: size.height * 0.3,
        ),
        const Radius.circular(24),
      ),
      _groupPaint(['upperBody', 'upperClothing', 'back']),
    );
    final limb = _groupPaint(['armsHands', 'upperClothing', 'bodyAccessories'])
      ..strokeWidth = size.width * 0.09;
    canvas.drawLine(
      Offset(x - size.width * 0.18, size.height * 0.25),
      Offset(x - size.width * 0.28, size.height * 0.57),
      limb,
    );
    canvas.drawLine(
      Offset(x + size.width * 0.18, size.height * 0.25),
      Offset(x + size.width * 0.28, size.height * 0.57),
      limb,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, size.height * 0.52),
        width: size.width * 0.38,
        height: size.height * 0.2,
      ),
      _groupPaint(['hips', 'lowerClothing', 'outfit']),
    );
    final legs = _groupPaint(['legsFeet', 'lowerClothing'])
      ..strokeWidth = size.width * 0.12;
    canvas.drawLine(
      Offset(x - size.width * 0.09, size.height * 0.57),
      Offset(x - size.width * 0.12, size.height * 0.91),
      legs,
    );
    canvas.drawLine(
      Offset(x + size.width * 0.09, size.height * 0.57),
      Offset(x + size.width * 0.12, size.height * 0.91),
      legs,
    );
    final outfit = Path()
      ..moveTo(x - size.width * 0.18, size.height * 0.25)
      ..lineTo(x + size.width * 0.18, size.height * 0.25)
      ..lineTo(x + size.width * 0.29, size.height * 0.64)
      ..lineTo(x - size.width * 0.29, size.height * 0.64)
      ..close();
    canvas.drawPath(
      outfit,
      _groupPaint([
        'outfit',
        'upperClothing',
        'lowerClothing',
        'bodyAccessories',
        'back',
      ]),
    );
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.selectedRegionId != selectedRegionId ||
      !mapEquals(oldDelegate.completion, completion);
}

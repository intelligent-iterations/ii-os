import 'dart:convert';
import 'dart:ui' show Rect;

const int maxInpaintMaskRegions = 32;

String encodeInpaintMaskRegions(List<Rect> regions) {
  if (regions.isEmpty || regions.length > maxInpaintMaskRegions) {
    throw ArgumentError.value(
      regions.length,
      'regions',
      'must contain 1 to 32 regions',
    );
  }
  for (final region in regions) {
    final values = [region.left, region.top, region.width, region.height];
    if (values.any((value) => !value.isFinite || value < 0) ||
        region.width <= 0 ||
        region.height <= 0 ||
        region.right > 1.0001 ||
        region.bottom > 1.0001) {
      throw ArgumentError.value(
        region,
        'regions',
        'must be normalized inside the image',
      );
    }
  }
  return jsonEncode(
    regions
        .map(
          (region) => [
            _stableCoordinate(region.left),
            _stableCoordinate(region.top),
            _stableCoordinate(region.width),
            _stableCoordinate(region.height),
          ],
        )
        .toList(growable: false),
  );
}

List<Rect> decodeInpaintMaskRegions(Object? encoded) {
  if (encoded is! String || encoded.trim().isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final regions = <Rect>[];
  for (final raw in decoded.take(maxInpaintMaskRegions)) {
    if (raw is! List || raw.length != 4 || raw.any((value) => value is! num)) {
      continue;
    }
    final values = raw.cast<num>().map((value) => value.toDouble()).toList();
    final rect = Rect.fromLTWH(values[0], values[1], values[2], values[3]);
    if (rect.left < 0 ||
        rect.top < 0 ||
        rect.width <= 0 ||
        rect.height <= 0 ||
        rect.right > 1.0001 ||
        rect.bottom > 1.0001) {
      continue;
    }
    regions.add(rect);
  }
  return List<Rect>.unmodifiable(regions);
}

double _stableCoordinate(double value) =>
    double.parse(value.toStringAsFixed(8));

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/inpaint_mask.dart';

void main() {
  test('mask regions round trip for edit review recovery', () {
    const regions = [
      Rect.fromLTWH(.1, .2, .3, .25),
      Rect.fromLTWH(.6, .1, .15, .2),
    ];

    expect(
      decodeInpaintMaskRegions(encodeInpaintMaskRegions(regions)),
      regions,
    );
    expect(decodeInpaintMaskRegions('not-json'), isEmpty);
    expect(decodeInpaintMaskRegions('[[0.9,0.9,0.2,0.2]]'), isEmpty);
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;

Future<double> decodeImageAspectRatio(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    return height == 0 ? 1 : width / height;
  } on Object {
    return 1;
  }
}

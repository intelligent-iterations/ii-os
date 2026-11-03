part of 'composition_compiler.dart';

extension on EditorCompositionCompiler {
  Future<Uint8List> _normalizeCaptionPng(
    Uint8List source,
    EditorCaptionRasterRequest request,
    EditorRenderCancellationToken cancellation,
  ) {
    final work = _decodeAndEncodeCaptionPng(source, request, cancellation);
    final cancelled = cancellation.whenCancelled.then<Uint8List>((_) {
      throw const EditorRenderCancelledException();
    });
    final timeout = Completer<Uint8List>();
    final timer = Timer(limits.captionRasterTimeout, () {
      timeout.completeError(
        EditorValidationException(
          'Caption ${request.clip.id} PNG normalization timed out.',
        ),
      );
      cancellation.cancel();
    });
    return Future.any<Uint8List>([
      work,
      cancelled,
      timeout.future,
    ]).whenComplete(timer.cancel);
  }

  Future<Uint8List> _decodeAndEncodeCaptionPng(
    Uint8List source,
    EditorCaptionRasterRequest request,
    EditorRenderCancellationToken cancellation,
  ) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      cancellation.throwIfCancelled();
      codec = await ui.instantiateImageCodec(source);
      cancellation.throwIfCancelled();
      final frame = await codec.getNextFrame();
      image = frame.image;
      if (image.width != request.pixelWidth ||
          image.height != request.pixelHeight) {
        throw EditorValidationException(
          'Caption ${request.clip.id} decoded to unexpected dimensions.',
        );
      }
      cancellation.throwIfCancelled();
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      cancellation.throwIfCancelled();
      if (encoded == null) {
        throw EditorValidationException(
          'Caption ${request.clip.id} could not be normalized as PNG.',
        );
      }
      final bytes = Uint8List.fromList(
        encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
      );
      if (bytes.length > limits.maxCaptionRasterBytes ||
          !_isExpectedCaptionPng(
            bytes,
            expectedWidth: request.pixelWidth,
            expectedHeight: request.pixelHeight,
          )) {
        throw EditorValidationException(
          'Caption ${request.clip.id} normalized PNG is outside its bounds.',
        );
      }
      return bytes;
    } on EditorValidationException {
      rethrow;
    } on EditorRenderCancelledException {
      rethrow;
    } catch (_) {
      throw EditorValidationException(
        'Caption ${request.clip.id} PNG could not be decoded safely.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

part of 'composition_compiler.dart';

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _pngMaxChunks = 4096;

final Uint32List _pngCrcTable = Uint32List.fromList(
  List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc.isOdd ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
    return crc;
  }, growable: false),
);

bool _isExpectedCaptionPng(
  Uint8List bytes, {
  required int expectedWidth,
  required int expectedHeight,
}) {
  if (bytes.length < 57 || expectedWidth <= 0 || expectedHeight <= 0) {
    return false;
  }
  for (var index = 0; index < _pngSignature.length; index++) {
    if (bytes[index] != _pngSignature[index]) return false;
  }

  final data = ByteData.sublistView(bytes);
  var offset = _pngSignature.length;
  var chunkCount = 0;
  var seenHeader = false;
  var seenPalette = false;
  var seenImageData = false;
  var imageDataClosed = false;
  var imageDataBytes = 0;
  int? colorType;
  while (offset < bytes.length) {
    chunkCount++;
    if (chunkCount > _pngMaxChunks || bytes.length - offset < 12) return false;
    final length = data.getUint32(offset, Endian.big);
    final payloadStart = offset + 8;
    final payloadEnd = payloadStart + length;
    final chunkEnd = payloadEnd + 4;
    if (payloadEnd < payloadStart || chunkEnd > bytes.length) return false;
    if (!_validPngChunkType(bytes, offset + 4) ||
        !_validPngChunkCrc(bytes, data, offset + 4, payloadEnd)) {
      return false;
    }

    final isHeader = _pngChunkIs(bytes, offset + 4, 73, 72, 68, 82);
    final isPalette = _pngChunkIs(bytes, offset + 4, 80, 76, 84, 69);
    final isImageData = _pngChunkIs(bytes, offset + 4, 73, 68, 65, 84);
    final isEnd = _pngChunkIs(bytes, offset + 4, 73, 69, 78, 68);
    if (isHeader) {
      if (seenHeader || chunkCount != 1 || length != 13) return false;
      final width = data.getUint32(payloadStart, Endian.big);
      final height = data.getUint32(payloadStart + 4, Endian.big);
      final bitDepth = bytes[payloadStart + 8];
      colorType = bytes[payloadStart + 9];
      if (width != expectedWidth ||
          height != expectedHeight ||
          !_validPngPixelFormat(bitDepth, colorType) ||
          bytes[payloadStart + 10] != 0 ||
          bytes[payloadStart + 11] != 0 ||
          bytes[payloadStart + 12] > 1) {
        return false;
      }
      seenHeader = true;
    } else if (!seenHeader) {
      return false;
    } else if (isPalette) {
      if (seenPalette ||
          seenImageData ||
          length == 0 ||
          length > 768 ||
          length % 3 != 0) {
        return false;
      }
      if (colorType == 0 || colorType == 4) return false;
      seenPalette = true;
    } else if (isImageData) {
      if (imageDataClosed || (colorType == 3 && !seenPalette)) return false;
      seenImageData = true;
      imageDataBytes += length;
    } else if (isEnd) {
      return length == 0 &&
          seenImageData &&
          imageDataBytes > 0 &&
          chunkEnd == bytes.length;
    } else {
      if (_pngCriticalChunk(bytes[offset + 4])) return false;
      if (seenImageData) imageDataClosed = true;
    }
    offset = chunkEnd;
  }
  return false;
}

bool _validPngChunkType(Uint8List bytes, int offset) {
  for (var index = 0; index < 4; index++) {
    final value = bytes[offset + index];
    if (!((value >= 65 && value <= 90) || (value >= 97 && value <= 122))) {
      return false;
    }
  }
  return true;
}

bool _pngCriticalChunk(int firstByte) => firstByte >= 65 && firstByte <= 90;

bool _pngChunkIs(
  Uint8List bytes,
  int offset,
  int first,
  int second,
  int third,
  int fourth,
) =>
    bytes[offset] == first &&
    bytes[offset + 1] == second &&
    bytes[offset + 2] == third &&
    bytes[offset + 3] == fourth;

bool _validPngPixelFormat(int bitDepth, int colorType) => switch (colorType) {
  0 => const {1, 2, 4, 8, 16}.contains(bitDepth),
  2 || 4 || 6 => bitDepth == 8 || bitDepth == 16,
  3 => const {1, 2, 4, 8}.contains(bitDepth),
  _ => false,
};

bool _validPngChunkCrc(
  Uint8List bytes,
  ByteData data,
  int typeStart,
  int payloadEnd,
) {
  var crc = 0xffffffff;
  for (var index = typeStart; index < payloadEnd; index++) {
    crc = _pngCrcTable[(crc ^ bytes[index]) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) == data.getUint32(payloadEnd, Endian.big);
}

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../models/picked_media.dart';

Future<PickedMedia> readMediaUpload(
  XFile file, {
  required int pickedBytes,
  int? maxFileBytes,
  int? maxTotalBytes,
}) async {
  final declaredLength = await file.length();
  _validateLength(
    declaredLength,
    pickedBytes: pickedBytes,
    maxFileBytes: maxFileBytes,
    maxTotalBytes: maxTotalBytes,
  );
  final bytes = await file.readAsBytes();
  if (bytes.length != declaredLength) {
    throw const FormatException(
      'That file changed while it was being read. Choose it again.',
    );
  }
  return PickedMedia.fromUpload(file: file, bytes: Uint8List.fromList(bytes));
}

String describeAcceptedMediaTypes(List<XTypeGroup> types) {
  final extensions = <String>{
    for (final group in types) ...?group.extensions,
  }.toList()..sort();
  if (extensions.isEmpty) return 'Any file this field accepts.';
  return extensions.map((extension) => '.$extension').join('  ');
}

void _validateLength(
  int length, {
  required int pickedBytes,
  required int? maxFileBytes,
  required int? maxTotalBytes,
}) {
  if (length <= 0 ||
      (maxFileBytes != null && length > maxFileBytes) ||
      (maxTotalBytes != null && pickedBytes + length > maxTotalBytes)) {
    throw const FormatException(
      'Choose media within this field\u2019s file-size limit.',
    );
  }
}

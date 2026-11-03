import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

Future<String?> saveLocalEditorMp4({
  required Uint8List bytes,
  String name = 'ii-os-edited-video',
  bool promptForLocation = true,
}) => saveLocalEditorVideo(
  bytes: bytes,
  contentType: 'video/mp4',
  name: name,
  promptForLocation: promptForLocation,
);

Future<String?> saveLocalEditorVideo({
  required Uint8List bytes,
  required String contentType,
  String name = 'ii-os-edited-video',
  bool promptForLocation = true,
}) {
  if (bytes.isEmpty || name.isEmpty) {
    throw ArgumentError('A named, non-empty video is required.');
  }
  final format = switch (contentType) {
    'video/mp4' => (extension: 'mp4', mimeType: MimeType.mp4Video),
    'video/webm' => (extension: 'webm', mimeType: MimeType.webm),
    _ => throw ArgumentError('Unsupported local video type: $contentType'),
  };
  final saver = FileSaver.instance;
  if (promptForLocation && _supportsSaveAs) {
    return saver.saveAs(
      name: name,
      bytes: bytes,
      fileExtension: format.extension,
      mimeType: format.mimeType,
    );
  }
  return saver.saveFile(
    name: name,
    bytes: bytes,
    fileExtension: format.extension,
    mimeType: format.mimeType,
  );
}

bool get _supportsSaveAs =>
    kIsWeb ||
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

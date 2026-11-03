import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

import 'verified_artifact_media.dart';

final class VerifiedArtifactSaveFormat {
  const VerifiedArtifactSaveFormat({
    required this.extension,
    required this.mimeType,
    this.customMimeType,
  });

  final String extension;
  final MimeType mimeType;
  final String? customMimeType;
}

VerifiedArtifactSaveFormat verifiedArtifactSaveFormat(String contentType) =>
    switch (contentType.toLowerCase()) {
      'image/jpeg' => const VerifiedArtifactSaveFormat(
        extension: 'jpg',
        mimeType: MimeType.jpeg,
      ),
      'image/png' => const VerifiedArtifactSaveFormat(
        extension: 'png',
        mimeType: MimeType.png,
      ),
      'image/webp' => const VerifiedArtifactSaveFormat(
        extension: 'webp',
        mimeType: MimeType.webp,
      ),
      'video/mp4' => const VerifiedArtifactSaveFormat(
        extension: 'mp4',
        mimeType: MimeType.mp4Video,
      ),
      'video/webm' => const VerifiedArtifactSaveFormat(
        extension: 'webm',
        mimeType: MimeType.webm,
      ),
      'audio/mpeg' => const VerifiedArtifactSaveFormat(
        extension: 'mp3',
        mimeType: MimeType.mp3,
      ),
      'audio/wav' => const VerifiedArtifactSaveFormat(
        extension: 'wav',
        mimeType: MimeType.custom,
        customMimeType: 'audio/wav',
      ),
      'audio/flac' => const VerifiedArtifactSaveFormat(
        extension: 'flac',
        mimeType: MimeType.custom,
        customMimeType: 'audio/flac',
      ),
      _ => throw ArgumentError(
        'Unsupported generated media type: $contentType',
      ),
    };

String verifiedArtifactDownloadName(
  VerifiedArtifactMedia media, {
  required String fallbackName,
}) {
  final filename = media.filename.split('/').last;
  final extensionAt = filename.lastIndexOf('.');
  final original = extensionAt > 0
      ? filename.substring(0, extensionAt)
      : filename;
  final candidate = original.isEmpty ? fallbackName : original;
  final safe = candidate
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  if (safe.isEmpty) return 'ii-os-ghost-generation';
  return safe.length <= 100 ? safe : safe.substring(0, 100);
}

Future<String?> saveVerifiedArtifactMedia({
  required VerifiedArtifactMedia media,
  required String fallbackName,
  bool promptForLocation = true,
}) {
  if (media.bytes.isEmpty) {
    throw ArgumentError('Verified generated media bytes are required.');
  }
  final format = verifiedArtifactSaveFormat(media.detectedContentType);
  final name = verifiedArtifactDownloadName(media, fallbackName: fallbackName);
  final saver = FileSaver.instance;
  final arguments = (
    name: name,
    bytes: media.bytes,
    fileExtension: format.extension,
    mimeType: format.mimeType,
    customMimeType: format.customMimeType,
  );
  if (promptForLocation && _supportsSaveAs) {
    return saver.saveAs(
      name: arguments.name,
      bytes: arguments.bytes,
      fileExtension: arguments.fileExtension,
      mimeType: arguments.mimeType,
      customMimeType: arguments.customMimeType,
    );
  }
  return saver.saveFile(
    name: arguments.name,
    bytes: arguments.bytes,
    fileExtension: arguments.fileExtension,
    mimeType: arguments.mimeType,
    customMimeType: arguments.customMimeType,
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

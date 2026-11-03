import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../models/generation_history.dart';
import '../models/picked_media.dart';
import 'verified_artifact_media.dart';

typedef PickedLibraryMediaReader =
    Future<VerifiedArtifactMedia> Function(HistoryEntryModel entry);

/// The bytes and file identity behind one choice from the shared media picker.
///
/// Uploads already carry their bytes. Library choices carry immutable artifact
/// metadata and are downloaded only after the person chooses one. Keeping that
/// distinction here stops every creative screen from implementing a subtly
/// different source switch.
final class ReadPickedMedia {
  const ReadPickedMedia({
    required this.file,
    required this.bytes,
    required this.verifiedContentType,
  });

  final XFile file;
  final Uint8List bytes;

  /// Present only for library media whose bytes were verified against the
  /// workspace artifact metadata.
  final String? verifiedContentType;
}

Future<ReadPickedMedia> readPickedMedia(
  PickedMedia picked, {
  required PickedLibraryMediaReader readLibrary,
}) async {
  if (!picked.isFromLibrary) {
    return ReadPickedMedia(
      file: picked.upload!,
      bytes: picked.bytes!,
      verifiedContentType: null,
    );
  }

  final media = await readLibrary(picked.entry!);
  return ReadPickedMedia(
    file: XFile.fromData(
      media.bytes,
      name: media.filename,
      path: media.filename,
      mimeType: media.detectedContentType,
    ),
    bytes: media.bytes,
    verifiedContentType: media.detectedContentType,
  );
}

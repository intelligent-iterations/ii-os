import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'generation_history.dart';

/// Where a chosen asset came from.
enum MediaPickerSource {
  /// An asset the workspace already generated.
  library,

  /// A file from the operator's own device.
  upload,
}

/// One asset a person chose, from either source.
///
/// Every media field in the product needs the same two answers -- reuse
/// something the workspace made, or bring a file -- and each one had grown its
/// own half of that: some could only upload, some could only browse, and none
/// of them agreed on what a choice looked like coming back.
///
/// [source] is stored rather than inferred from which field is populated. A
/// caller that infers it gets it wrong exactly once, silently, in the branch
/// nobody exercised.
@immutable
final class PickedMedia {
  const PickedMedia._({
    required this.source,
    this.entry,
    this.upload,
    this.bytes,
  });

  /// An asset chosen out of the workspace library.
  factory PickedMedia.fromLibrary(HistoryEntryModel entry) =>
      PickedMedia._(source: MediaPickerSource.library, entry: entry);

  /// A file chosen from the device.
  ///
  /// The bytes travel with the file because every caller needs them and
  /// reading an [XFile] twice on web is a second network round trip.
  factory PickedMedia.fromUpload({
    required XFile file,
    required Uint8List bytes,
  }) => PickedMedia._(
    source: MediaPickerSource.upload,
    upload: file,
    bytes: bytes,
  );

  final MediaPickerSource source;

  /// Set when [source] is [MediaPickerSource.library].
  final HistoryEntryModel? entry;

  /// Set when [source] is [MediaPickerSource.upload].
  final XFile? upload;

  /// Set when [source] is [MediaPickerSource.upload].
  final Uint8List? bytes;

  bool get isFromLibrary => source == MediaPickerSource.library;

  /// What to show a person who has chosen this -- a prompt for a generation, a
  /// file name for an upload.
  String get label => switch (source) {
    MediaPickerSource.library =>
      entry!.generation.prompt.trim().isEmpty
          ? entry!.filename
          : entry!.generation.prompt.trim(),
    MediaPickerSource.upload => upload!.name,
  };
}

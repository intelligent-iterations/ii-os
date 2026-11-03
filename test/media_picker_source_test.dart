import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/generation_history.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/picked_media.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/media_upload_reader.dart';
import 'package:ii_os/services/picked_media_reader.dart';
import 'package:ii_os/services/verified_artifact_media.dart';

JsonMap _job() => {
  'jobId': 'job-a',
  'repository': 'acme/media',
  'status': 'completed',
  'submittedAt': '2026-08-16T12:00:00Z',
  'generationMetadata': {'model': 'Z-Image Turbo', 'prompt': 'a rooftop'},
  'artifacts': [
    {
      'path': 'workspaces/w/runs/job-a/media/job-a.png',
      'content_type': 'image/png',
      'generation': '1786900000000000',
    },
  ],
};

HistoryEntryModel _entry() {
  final job = _job();
  return HistoryEntryModel.fromJobArtifact(
    job: job,
    artifact: (job['artifacts']! as List).first as JsonMap,
    poster: null,
  );
}

void main() {
  group('PickedMedia', () {
    test('a library pick carries the entry it came from', () {
      final entry = _entry();
      final picked = PickedMedia.fromLibrary(entry);

      expect(picked.entry, same(entry));
      expect(picked.upload, isNull);
      expect(picked.bytes, isNull);
      expect(picked.isFromLibrary, isTrue);
    });

    test('an upload carries the file and the bytes already read', () {
      // The bytes travel with the file because every caller needs them and
      // reading an XFile twice on web is a second network round trip.
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = XFile.fromData(
        bytes,
        name: 'shot.png',
        path: 'shot.png',
        mimeType: 'image/png',
      );
      final picked = PickedMedia.fromUpload(file: file, bytes: bytes);

      expect(picked.upload?.name, 'shot.png');
      expect(picked.bytes, bytes);
      expect(picked.entry, isNull);
      expect(picked.isFromLibrary, isFalse);
    });

    test('a pick names its own kind rather than making callers infer it', () {
      // A caller that infers the source from which field is non-null gets it
      // wrong exactly once, silently, in the branch nobody exercised.
      expect(
        PickedMedia.fromLibrary(_entry()).source,
        MediaPickerSource.library,
      );
      expect(
        PickedMedia.fromUpload(
          file: XFile.fromData(Uint8List(0), name: 'a.png', path: 'a.png'),
          bytes: Uint8List(0),
        ).source,
        MediaPickerSource.upload,
      );
    });

    test(
      'an upload is already read and never calls the library reader',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final file = XFile.fromData(
          bytes,
          name: 'voice.wav',
          path: 'voice.wav',
        );
        var libraryReads = 0;

        final selected = await readPickedMedia(
          PickedMedia.fromUpload(file: file, bytes: bytes),
          readLibrary: (_) async {
            libraryReads++;
            return _verifiedMedia(bytes);
          },
        );

        expect(selected.file, same(file));
        expect(selected.bytes, same(bytes));
        expect(selected.verifiedContentType, isNull);
        expect(libraryReads, 0);
      },
    );

    test(
      'a library choice resolves its immutable artifact bytes once',
      () async {
        final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
        var libraryReads = 0;

        final selected = await readPickedMedia(
          PickedMedia.fromLibrary(_entry()),
          readLibrary: (_) async {
            libraryReads++;
            return _verifiedMedia(bytes);
          },
        );

        expect(selected.file.name, 'library.png');
        expect(selected.bytes, same(bytes));
        expect(selected.verifiedContentType, 'image/png');
        expect(libraryReads, 1);
      },
    );
  });

  group('readMediaUpload', () {
    test('reads an accepted file once into the shared picker result', () async {
      final picked = await readMediaUpload(
        XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'voice.wav',
          path: 'voice.wav',
        ),
        pickedBytes: 4,
        maxFileBytes: 3,
        maxTotalBytes: 7,
      );

      expect(picked.upload?.name, 'voice.wav');
      expect(picked.bytes, [1, 2, 3]);
    });

    test('rejects a file that exceeds the field limit', () async {
      final file = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'large.wav',
      );

      await expectLater(
        readMediaUpload(file, pickedBytes: 0, maxFileBytes: 2),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        readMediaUpload(file, pickedBytes: 2, maxTotalBytes: 4),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

VerifiedArtifactMedia _verifiedMedia(Uint8List bytes) => VerifiedArtifactMedia(
  identity: const ArtifactAuthorizationIdentity(
    workspaceId: 'w',
    jobId: 'job-a',
    bucket: 'workspace-media',
    objectName: 'workspaces/w/runs/job-a/media/library.png',
    generation: '1',
    sizeBytes: 4,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    contentType: 'image/png',
  ),
  filename: 'library.png',
  detectedContentType: 'image/png',
  bytes: bytes,
);

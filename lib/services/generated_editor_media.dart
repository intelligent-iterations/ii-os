import 'dart:typed_data';

import '../models/generation_history.dart';
import 'api_client.dart';
import 'artifact_read_url_cache.dart';
import 'editor_media_source.dart';
import 'verified_artifact_media.dart';

final class GeneratedEditorMedia {
  const GeneratedEditorMedia({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String filename;
  final String contentType;
  final Uint8List bytes;
}

Future<GeneratedEditorMedia> downloadGeneratedEditorMedia({
  required ApiClient api,
  required ArtifactReadGrant grant,
  required HistoryEntryModel entry,
  required String workspaceId,
  required String expectedBucket,
}) async {
  final entrySize = _positiveInt(entry.artifact['size_bytes']);
  final entryDigest = entry.artifact['sha256']?.toString().toLowerCase();
  final expectedPrefix = 'workspaces/$workspaceId/runs/${entry.jobId}/';
  if (workspaceId.isEmpty ||
      expectedBucket.isEmpty ||
      entry.jobId.isEmpty ||
      entry.objectName.isEmpty ||
      !entry.objectName.startsWith(expectedPrefix) ||
      !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(entry.generationId) ||
      !entry.isGeneratedMedia ||
      entrySize == null ||
      entrySize > maxEditorSourceBytes ||
      entryDigest == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(entryDigest)) {
    throw const FormatException(
      'The selected generated asset is unavailable for local editing.',
    );
  }
  final expected = ArtifactAuthorizationIdentity(
    workspaceId: workspaceId,
    jobId: entry.jobId,
    bucket: expectedBucket,
    objectName: entry.objectName,
    generation: entry.generationId,
    sizeBytes: entrySize,
    sha256: entryDigest,
    contentType: entry.contentType,
  );
  final verified = await downloadVerifiedArtifactMedia(
    api: api,
    grant: grant,
    expected: expected,
    maxBytes: maxEditorSourceBytes,
  );
  return GeneratedEditorMedia(
    filename: entry.filename.isEmpty ? 'generated-media' : entry.filename,
    contentType: verified.detectedContentType,
    bytes: verified.bytes,
  );
}

int? _positiveInt(Object? value) {
  final parsed = switch (value) {
    int number => number,
    num number when number.isFinite && number == number.truncateToDouble() =>
      number.toInt(),
    String text when RegExp(r'^[1-9][0-9]*$').hasMatch(text.trim()) =>
      int.tryParse(text.trim()),
    _ => null,
  };
  return parsed != null && parsed > 0 ? parsed : null;
}

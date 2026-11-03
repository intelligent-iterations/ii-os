import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'artifact_read_url_cache.dart';

/// The only document type a workflow may report, and its hard ceiling.
const artifactDocumentContentType = 'application/json';
const maxArtifactDocumentBytes = 1024 * 1024;

typedef ArtifactBytesFetcher =
    Future<Uint8List> Function(Uri uri, {required int maxBytes});

/// Downloads a small JSON result directly from workspace storage and proves it
/// is the exact object the workflow reported before parsing it.
///
/// This is deliberately separate from media: a document is never cached with
/// media, never content-sniffed as media, and is bounded at 1 MiB.
Future<Object?> downloadVerifiedJsonDocument({
  required ArtifactBytesFetcher fetch,
  required ArtifactReadGrant grant,
  required ArtifactAuthorizationIdentity expected,
}) async {
  final uri = Uri.tryParse(grant.url);
  if (uri == null ||
      expected.contentType != artifactDocumentContentType ||
      expected.sizeBytes <= 0 ||
      expected.sizeBytes > maxArtifactDocumentBytes ||
      !expected.matches(grant) ||
      !grant.expiresAt.isAfter(DateTime.now().toUtc()) ||
      !signedArtifactUrlIdentityMatches(
        uri,
        bucket: expected.bucket,
        objectName: expected.objectName,
        generation: expected.generation,
      ) ||
      !signedArtifactUrlExpiryMatches(uri, grant.expiresAt)) {
    throw const FormatException(
      'The workspace result authorization is invalid.',
    );
  }
  final bytes = await fetch(uri, maxBytes: expected.sizeBytes);
  if (bytes.length != expected.sizeBytes ||
      sha256.convert(bytes).toString() != expected.sha256) {
    throw const FormatException(
      'The workspace result does not match its immutable metadata.',
    );
  }
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const FormatException('The workspace result is not valid JSON.');
  }
}

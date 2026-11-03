import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/models.dart';
import 'api_client.dart';

final class BugReportScreenshot {
  const BugReportScreenshot({
    required this.filename,
    required this.bytes,
    required this.contentType,
  });

  final String filename;
  final Uint8List bytes;
  final String contentType;
}

final class BugReportDraft {
  const BugReportDraft({
    required this.description,
    required this.expectedBehavior,
    required this.route,
    required this.clientPlatform,
    required this.screenshot,
  });

  final String description;
  final String expectedBehavior;
  final String route;
  final String clientPlatform;
  final BugReportScreenshot? screenshot;
}

final class BugReportClient {
  const BugReportClient(this.api);

  final ApiClient api;

  Future<String> submit({
    required String workspaceId,
    required BugReportDraft draft,
  }) async {
    final screenshotId = draft.screenshot == null
        ? null
        : await _uploadScreenshot(workspaceId, draft.screenshot!);
    final response = await api.post(
      'v1/workspaces/$workspaceId/bug-reports',
      body: {
        'description': draft.description,
        'expectedBehavior': draft.expectedBehavior,
        'route': draft.route,
        'clientPlatform': draft.clientPlatform,
        'screenshotId': screenshotId,
      },
    );
    final reportId = asJsonMap(response['data'])['reportId'] as String? ?? '';
    if (reportId.isEmpty) {
      throw const FormatException(
        'The ii-os control API returned an invalid bug report receipt.',
      );
    }
    return reportId;
  }

  Future<String> _uploadScreenshot(
    String workspaceId,
    BugReportScreenshot screenshot,
  ) async {
    final createdResponse = await api.post(
      'v1/workspaces/$workspaceId/bug-reports/screenshots',
      body: {
        'filename': screenshot.filename,
        'contentType': screenshot.contentType,
        'sizeBytes': screenshot.bytes.length,
        'sha256': sha256.convert(screenshot.bytes).toString(),
      },
    );
    final created = asJsonMap(createdResponse['data']);
    final screenshotId = created['screenshotId'] as String? ?? '';
    final uploadUri = Uri.tryParse(created['uploadUrl'] as String? ?? '');
    final headers = _stringMap(created['uploadHeaders']);
    if (screenshotId.isEmpty || uploadUri == null || !_isGcsUrl(uploadUri)) {
      throw const FormatException(
        'The ii-os control API returned an invalid screenshot upload grant.',
      );
    }
    await api.putBytes(uploadUri, screenshot.bytes, headers: headers);
    await api.post(
      'v1/workspaces/$workspaceId/bug-reports/screenshots/'
      '$screenshotId/complete',
    );
    return screenshotId;
  }
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}

bool _isGcsUrl(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'storage.googleapis.com' ||
        uri.host.endsWith('.storage.googleapis.com'));

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'asset_url_signer.dart';
import 'data_plane_connection.dart';
import 'retention.dart';
import 'retention_policy.dart';
import 'workspace_store.dart';

final class BugReportService {
  BugReportService({required this.store});

  final WorkspaceStore store;
  final Uuid _uuid = const Uuid();

  Future<Map<String, Object?>> createScreenshotUpload({
    required String workspaceId,
    required String actorUid,
    required Map<String, Object?> request,
    int retentionDays = defaultArtifactRetentionDays,
  }) async {
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    final spec = BugReportScreenshotSpec.parse(request);
    final screenshotId = _uuid.v4();
    final objectName =
        'workspaces/$workspaceId/bug-reports/$screenshotId/'
        '${spec.safeFilename}';
    final grant = await AssetUrlSigner(connection).signWriteUrl(
      objectName: objectName,
      contentType: spec.contentType,
      sha256Hex: spec.sha256,
    );
    final now = DateTime.now().toUtc();
    final data = <String, Object?>{
      'screenshotId': screenshotId,
      'workspaceId': workspaceId,
      'bucket': connection.bucket,
      'path': objectName,
      'filename': spec.safeFilename,
      'contentType': spec.contentType,
      'sizeBytes': spec.sizeBytes,
      'sha256': spec.sha256,
      'status': 'pending',
      'reportId': null,
      'createdBy': actorUid,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(
        now.add(
          Duration(
            days: retentionDays.clamp(
              minArtifactRetentionDays,
              maxArtifactRetentionDays,
            ),
          ),
        ),
      ),
    };
    await store.firestore
        .collection('bugReportScreenshots')
        .doc(screenshotId)
        .create(data);
    return {
      ..._public(data),
      'uploadUrl': grant.url,
      'uploadHeaders': grant.headers,
      'uploadExpiresAt': grant.expiresAt.toIso8601String(),
    };
  }

  Future<Map<String, Object?>> completeScreenshotUpload({
    required String workspaceId,
    required String actorUid,
    required String screenshotId,
  }) async {
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    final ref = store.firestore
        .collection('bugReportScreenshots')
        .doc(screenshotId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    _requireOwnedScreenshot(data, workspaceId, actorUid);
    if (data!['status'] == 'ready') return _public(data);

    final verified = connection.emulated
        ? <String, Object?>{'generation': '1', 'crc32c': 'emulated'}
        : await _verifyRemote(connection, data);
    final now = Timestamp.now();
    await ref.update({
      'status': 'ready',
      ...verified,
      'verifiedAt': now,
      'updatedAt': now,
    });
    return _public({...data, 'status': 'ready', ...verified, 'updatedAt': now});
  }

  Future<Map<String, Object?>> createReport({
    required String workspaceId,
    required String actorUid,
    required String actorEmail,
    required Map<String, Object?> request,
  }) async {
    final input = BugReportInput.parse(request);
    final reportId = _uuid.v4();
    final reportRef = store.firestore.collection('bugReports').doc(reportId);
    final now = Timestamp.now();
    final baseData = <String, Object?>{
      'reportId': reportId,
      'workspaceId': workspaceId,
      'description': input.description,
      'expectedBehavior': input.expectedBehavior,
      'route': input.route,
      'clientPlatform': input.clientPlatform,
      'status': 'new',
      'reportedBy': actorUid,
      'reporterEmail': actorEmail,
      'createdAt': now,
      'updatedAt': now,
    };
    final screenshotId = input.screenshotId;
    if (screenshotId == null) {
      await reportRef.create({...baseData, 'screenshot': null});
      return _publicReport(baseData);
    }

    final screenshotRef = store.firestore
        .collection('bugReportScreenshots')
        .doc(screenshotId);
    await store.firestore.runTransaction<void>((transaction) async {
      final screenshotSnapshot = await transaction.get(screenshotRef);
      final screenshot = screenshotSnapshot.data();
      _requireOwnedScreenshot(screenshot, workspaceId, actorUid);
      if (screenshot!['status'] != 'ready') {
        throw const ApiError(
          409,
          'bug_report_screenshot_not_ready',
          'Finish uploading the screenshot before sending the report.',
        );
      }
      if (screenshot['reportId'] != null) {
        throw const ApiError(
          409,
          'bug_report_screenshot_used',
          'This screenshot is already attached to a report.',
        );
      }
      transaction.create(reportRef, {
        ...baseData,
        'screenshot': {
          'screenshotId': screenshotId,
          'bucket': screenshot['bucket'],
          'path': screenshot['path'],
          'generation': screenshot['generation'],
          'filename': screenshot['filename'],
          'contentType': screenshot['contentType'],
          'sizeBytes': screenshot['sizeBytes'],
        },
      });
      transaction.update(screenshotRef, {
        'reportId': reportId,
        'updatedAt': now,
      });
    });
    return _publicReport(baseData);
  }

  Future<Map<String, Object?>> _verifyRemote(
    DataPlaneConnection connection,
    Map<String, Object?> data,
  ) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final remote = await storage.StorageApi(
        client,
      ).objects.get(connection.bucket, data['path']! as String);
      if (remote is! storage.Object ||
          remote.contentType != data['contentType'] ||
          remote.size != data['sizeBytes'].toString() ||
          remote.metadata?['ii-os-sha256'] != data['sha256'] ||
          remote.generation == null) {
        throw const ApiError(
          409,
          'bug_report_screenshot_verification_failed',
          'The uploaded screenshot does not match its upload request.',
        );
      }
      return {'generation': remote.generation, 'crc32c': remote.crc32c};
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        409,
        'bug_report_screenshot_verification_failed',
        'The uploaded screenshot could not be verified.',
      );
    } finally {
      client.close();
    }
  }
}

final class BugReportInput {
  const BugReportInput({
    required this.description,
    required this.expectedBehavior,
    required this.route,
    required this.clientPlatform,
    required this.screenshotId,
  });

  factory BugReportInput.parse(Map<String, Object?> value) {
    final description = _boundedText(
      value['description'],
      field: 'description',
      maxLength: 4000,
      required: true,
    );
    final expectedBehavior = _boundedText(
      value['expectedBehavior'],
      field: 'expectedBehavior',
      maxLength: 2000,
    );
    final route = _boundedText(value['route'], field: 'route', maxLength: 1000);
    if (route != null && !route.startsWith('/')) {
      throw const ApiError(
        400,
        'invalid_bug_report',
        'The bug report route must be an app-relative path.',
      );
    }
    final platform = _boundedText(
      value['clientPlatform'],
      field: 'clientPlatform',
      maxLength: 20,
    );
    const platforms = {
      'web',
      'android',
      'ios',
      'macos',
      'windows',
      'linux',
      'unknown',
    };
    if (platform != null && !platforms.contains(platform)) {
      throw const ApiError(
        400,
        'invalid_bug_report',
        'The bug report client platform is invalid.',
      );
    }
    final screenshotId = _boundedText(
      value['screenshotId'],
      field: 'screenshotId',
      maxLength: 100,
    );
    if (screenshotId != null &&
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(screenshotId)) {
      throw const ApiError(
        400,
        'invalid_bug_report',
        'The bug report screenshot reference is invalid.',
      );
    }
    return BugReportInput(
      description: description!,
      expectedBehavior: expectedBehavior,
      route: route,
      clientPlatform: platform ?? 'unknown',
      screenshotId: screenshotId,
    );
  }

  final String description;
  final String? expectedBehavior;
  final String? route;
  final String clientPlatform;
  final String? screenshotId;
}

final class BugReportScreenshotSpec {
  const BugReportScreenshotSpec({
    required this.safeFilename,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
  });

  factory BugReportScreenshotSpec.parse(Map<String, Object?> value) {
    final filename = value['filename'];
    final contentType = value['contentType'];
    final size = value['sizeBytes'];
    final sha = value['sha256'];
    if (filename is! String ||
        filename.trim().isEmpty ||
        filename.length > 255 ||
        contentType is! String ||
        !_screenshotContentTypes.containsKey(contentType) ||
        size is! num ||
        size.toInt() != size ||
        size <= 0 ||
        size > 10 * 1024 * 1024 ||
        sha is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha.toLowerCase())) {
      throw const ApiError(
        400,
        'invalid_bug_report_screenshot',
        'Screenshot metadata is invalid.',
      );
    }
    final basename = filename.trim().split(RegExp(r'[/\\]')).last;
    final stem = basename
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]{1,8}$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
    final safeStem = stem.isEmpty ? 'bug-screenshot' : stem;
    final boundedStem = safeStem.length > 100
        ? safeStem.substring(0, 100)
        : safeStem;
    return BugReportScreenshotSpec(
      safeFilename: '$boundedStem.${_screenshotContentTypes[contentType]}',
      contentType: contentType,
      sizeBytes: size.toInt(),
      sha256: sha.toLowerCase(),
    );
  }

  final String safeFilename;
  final String contentType;
  final int sizeBytes;
  final String sha256;
}

String? _boundedText(
  Object? value, {
  required String field,
  required int maxLength,
  bool required = false,
}) {
  if (value == null && !required) return null;
  if (value is! String) {
    throw ApiError(400, 'invalid_bug_report', '$field must be text.');
  }
  final normalized = value.trim();
  if ((required && normalized.isEmpty) || normalized.length > maxLength) {
    throw ApiError(400, 'invalid_bug_report', '$field is invalid.');
  }
  return normalized.isEmpty ? null : normalized;
}

void _requireOwnedScreenshot(
  Map<String, Object?>? data,
  String workspaceId,
  String actorUid,
) {
  if (data == null ||
      data['workspaceId'] != workspaceId ||
      data['createdBy'] != actorUid ||
      recordRetentionExpired(data)) {
    throw const ApiError(
      404,
      'bug_report_screenshot_not_found',
      'Bug report screenshot not found.',
    );
  }
}

Map<String, Object?> _public(Map<String, Object?> data) => data.map(
  (key, value) => MapEntry(
    key,
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : value,
  ),
)..remove('createdBy');

Map<String, Object?> _publicReport(Map<String, Object?> data) => {
  'reportId': data['reportId'],
  'status': data['status'],
  'createdAt': data['createdAt'] is Timestamp
      ? (data['createdAt']! as Timestamp).toDate().toUtc().toIso8601String()
      : data['createdAt'],
};

const _screenshotContentTypes = <String, String>{
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

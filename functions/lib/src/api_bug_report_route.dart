part of 'api.dart';

extension _BugReportRoute on IiOsApi {
  Future<Response> _bugReportRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    await store.requireAccess(actor, workspaceId, Capability.workspaceRead);
    final workspace = await store.getWorkspace(workspaceId);
    if (path.length == 4 && request.method == 'POST') {
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'bug_report.create',
        targetType: 'bug_report',
        metadata: {
          'hasScreenshot': body['screenshotId'] != null,
          'clientPlatform': _bugReportPlatformForAudit(body['clientPlatform']),
        },
        execute: () => bugReports.createReport(
          workspaceId: workspaceId,
          actorUid: actor.uid,
          actorEmail: actor.email,
          request: body,
        ),
      );
    }
    if (path.length == 5 &&
        path[4] == 'screenshots' &&
        request.method == 'POST') {
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'bug_report.screenshot.upload.create',
        targetType: 'gcs_bug_report_screenshot',
        targetId: requestId,
        execute: () => bugReports.createScreenshotUpload(
          workspaceId: workspaceId,
          actorUid: actor.uid,
          request: body,
          retentionDays: artifactRetentionDays(
            workspace.artifactStorage?.retentionDays,
          ),
        ),
      );
    }
    if (path.length == 7 &&
        path[4] == 'screenshots' &&
        path[6] == 'complete' &&
        request.method == 'POST') {
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'bug_report.screenshot.upload.complete',
        targetType: 'gcs_bug_report_screenshot',
        targetId: path[5],
        execute: () => bugReports.completeScreenshotUpload(
          workspaceId: workspaceId,
          actorUid: actor.uid,
          screenshotId: path[5],
        ),
      );
    }
    throw const ApiError(404, 'not_found', 'Bug report route not found.');
  }
}

String _bugReportPlatformForAudit(Object? value) {
  if (value is! String || value.length > 20) return 'unknown';
  return value;
}

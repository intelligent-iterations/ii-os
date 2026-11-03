part of 'workflow_api.dart';

extension WorkflowAudit on WorkflowApi {
  Future<Response> _audited({
    required String requestId,
    required AuthenticatedUser actor,
    required String workspaceId,
    required String action,
    required String targetType,
    required FutureOr<Object?> Function() execute,
    String? targetId,
    Map<String, Object?> metadata = const {},
  }) async {
    await audit.record(
      requestId: requestId,
      actor: actor,
      action: action,
      phase: 'requested',
      workspaceId: workspaceId,
      targetType: targetType,
      targetId: targetId,
      metadata: metadata,
    );
    try {
      final result = await execute();
      try {
        await audit.record(
          requestId: requestId,
          actor: actor,
          action: action,
          phase: 'succeeded',
          workspaceId: workspaceId,
          targetType: targetType,
          targetId: targetId,
          metadata: metadata,
        );
      } on ApiError catch (error) {
        print('ii-os workflow audit warning for $requestId: ${error.code}');
      }
      return jsonResponse(200, {'data': result}, requestId: requestId);
    } catch (error) {
      final code = error is ApiError
          ? error.code
          : error.runtimeType.toString();
      try {
        await audit.record(
          requestId: requestId,
          actor: actor,
          action: action,
          phase: 'failed',
          workspaceId: workspaceId,
          targetType: targetType,
          targetId: targetId,
          metadata: {...metadata, 'errorCode': code},
        );
      } on ApiError {
        // Preserve the operation error after the requested audit is durable.
      }
      rethrow;
    }
  }
}

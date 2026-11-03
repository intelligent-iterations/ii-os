part of 'api.dart';

extension _ApiAuditSupport on IiOsApi {
  Future<Response> _audited({
    required String requestId,
    required AuthenticatedUser actor,
    required String action,
    required String targetType,
    required FutureOr<Object?> Function() execute,
    String? workspaceId,
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
        print('ii-os success audit warning for $requestId: ${error.code}');
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
        // The requested row is durable, so preserve the operation error.
      }
      rethrow;
    }
  }
}

part of 'api.dart';

extension _ApiErrorSupport on IiOsApi {
  Future<Response> _clientErrorRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
  ) async {
    return handleClientErrorReport(
      request: request,
      requestId: requestId,
      actor: actor,
      rateLimiter: clientErrorRateLimiter,
      errors: errors,
    );
  }

  Future<void> _reportApiError(
    ApiError error,
    StackTrace stackTrace,
    Request request,
    List<String> path,
    String requestId,
    AuthenticatedUser? actor,
  ) async {
    if (error.status < 500) return;
    await errors.report(
      _requestErrorEvent(
        errorType: error.code,
        message: error.diagnostic ?? error.message,
        stackTrace: stackTrace,
        request: request,
        path: path,
        requestId: requestId,
        actor: actor,
      ),
    );
  }

  Future<void> _reportUnhandledRequestError(
    Object error,
    StackTrace stackTrace,
    Request request,
    List<String> path,
    String requestId,
    AuthenticatedUser? actor,
  ) => errors.report(
    _requestErrorEvent(
      errorType: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stackTrace,
      request: request,
      path: path,
      requestId: requestId,
      actor: actor,
    ),
  );
}

Future<Response> handleClientErrorReport({
  required Request request,
  required String requestId,
  required AuthenticatedUser actor,
  required ClientErrorRateLimiter rateLimiter,
  required ErrorReporter errors,
  DateTime Function()? clock,
}) async {
  final body = await readJsonObject(request);
  if (!rateLimiter.allow(actor.uid)) {
    throw const ApiError(
      429,
      'client_error_rate_limited',
      'Too many client errors were submitted. Try again later.',
    );
  }
  final schemaVersion = body['schemaVersion'];
  if (schemaVersion != null && schemaVersion != errorEventSchema) {
    throw const ApiError(
      400,
      'invalid_client_error_schema',
      'Client error schema is invalid.',
    );
  }
  final now = (clock ?? DateTime.now)().toUtc();
  final workspaceId = _optionalClientErrorField(
    body,
    'workspaceId',
    maxLength: 120,
  );
  await errors.report(
    ErrorEvent(
      source: requiredString(body, 'source', maxLength: 80),
      errorType: requiredString(body, 'errorType', maxLength: 120),
      message: requiredString(body, 'message', maxLength: 1200),
      stackTrace:
          _optionalClientErrorField(body, 'stackTrace', maxLength: 5000) ?? '',
      requestId: requestId,
      route: _optionalClientErrorField(body, 'route', maxLength: 300) ?? '',
      occurredAt: parseClientErrorOccurredAt(body['occurredAt'], now: now),
      relatedRequestId: _optionalClientErrorField(
        body,
        'relatedRequestId',
        maxLength: 100,
      ),
      breadcrumbs: ErrorBreadcrumb.parseList(body['breadcrumbs'], now: now),
      workspaceId: workspaceId,
      actorUid: actor.uid,
    ),
  );
  return jsonResponse(202, {'accepted': true}, requestId: requestId);
}

ErrorEvent _requestErrorEvent({
  required String errorType,
  required String message,
  required StackTrace stackTrace,
  required Request request,
  required List<String> path,
  required String requestId,
  required AuthenticatedUser? actor,
}) => ErrorEvent(
  source: 'api',
  errorType: errorType,
  message: message,
  stackTrace: stackTrace.toString(),
  requestId: requestId,
  route: '${request.method} /${path.map(Uri.encodeComponent).join('/')}',
  actorUid: actor?.uid,
);

String? _optionalClientErrorField(
  Map<String, Object?> body,
  String key, {
  required int maxLength,
}) {
  final value = body[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw ApiError(400, 'invalid_$key', '$key is invalid.');
  }
  return value.trim();
}

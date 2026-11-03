part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _passwordlessAuthRoute(
    Request request,
    String requestId,
    List<String> path,
  ) async {
    if (path.length != 4 ||
        path[0] != 'v1' ||
        path[1] != 'auth' ||
        path[2] != 'otp') {
      return null;
    }
    if (request.method != 'POST') {
      throw const ApiError(
        405,
        'method_not_allowed',
        'Use POST for passwordless sign-in.',
      );
    }
    _requireTrustedOrigin(request);
    final body = await readJsonObject(request);
    final result = switch (path[3]) {
      'start' => await passwordlessAuth.start(
        email: requiredString(body, 'email', maxLength: 254),
        clientNonce: requiredString(body, 'clientNonce', maxLength: 100),
        clientIp: _clientIp(request),
      ),
      'verify' => await passwordlessAuth.verify(
        challengeId: requiredString(body, 'challengeId', maxLength: 40),
        code: requiredString(body, 'code', maxLength: 6),
        clientNonce: requiredString(body, 'clientNonce', maxLength: 100),
      ),
      'exchange' => await passwordlessAuth.exchange(
        challengeId: requiredString(body, 'challengeId', maxLength: 40),
        magicExchange: requiredString(body, 'magicExchange', maxLength: 100),
        clientNonce: requiredString(body, 'clientNonce', maxLength: 100),
      ),
      _ => throw const ApiError(404, 'not_found', 'API route not found.'),
    };
    return jsonResponse(200, result, requestId: requestId);
  }

  void _requireTrustedOrigin(Request request) {
    final origin = request.headers['origin']?.trim();
    if (origin != null && origin.isNotEmpty && origin != webOrigin) {
      throw const ApiError(
        403,
        'untrusted_origin',
        'This sign-in request came from an untrusted origin.',
      );
    }
  }
}

String _clientIp(Request request) {
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded == null || forwarded.trim().isEmpty) return 'unknown';
  final first = forwarded.split(',').first.trim();
  return first.isEmpty ? 'unknown' : first.substring(0, min(first.length, 64));
}

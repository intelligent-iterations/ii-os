part of 'api.dart';

extension _NotificationRoutes on IiOsApi {
  Future<Response?> _notificationRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    List<String> path,
  ) async {
    if (request.method == 'GET' && _matches(path, ['v1', 'notifications'])) {
      return jsonResponse(200, {
        'notifications': await notifications.listForUser(actor.uid),
      }, requestId: requestId);
    }
    if (request.method == 'POST' &&
        path.length == 4 &&
        path[0] == 'v1' &&
        path[1] == 'notifications' &&
        path[3] == 'read') {
      await notifications.markRead(actor.uid, Uri.decodeComponent(path[2]));
      return jsonResponse(200, {'read': true}, requestId: requestId);
    }
    if (request.method == 'POST' &&
        _matches(path, ['v1', 'notifications', 'read-all'])) {
      await notifications.markAllRead(actor.uid);
      return jsonResponse(200, {'read': true}, requestId: requestId);
    }
    if (_matches(path, ['v1', 'notification-devices'])) {
      final body = await readJsonObject(request);
      final token = requiredString(body, 'token', maxLength: 4096);
      if (request.method == 'POST') {
        await notifications.registerDevice(
          uid: actor.uid,
          token: token,
          platform: requiredString(body, 'platform', maxLength: 30),
        );
        return jsonResponse(200, {'registered': true}, requestId: requestId);
      }
      if (request.method == 'DELETE') {
        await notifications.unregisterDevice(uid: actor.uid, token: token);
        return jsonResponse(200, {'registered': false}, requestId: requestId);
      }
    }
    return null;
  }
}

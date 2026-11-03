import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

import '../../api_error.dart';
import '../../session_relay_control.dart';

final class HttpSessionRelayControl implements SessionRelayControl {
  HttpSessionRelayControl({
    required Uri baseUri,
    required String controlSecret,
    http.Client? client,
  }) : _baseUri = _validatedBase(baseUri),
       _controlSecret = _validatedSecret(controlSecret),
       _client = client ?? http.Client();

  final Uri _baseUri;
  final String _controlSecret;
  final http.Client _client;

  @override
  Uri connectUri(String sessionId) => _uri([
    'v1',
    'connect',
    _segment(sessionId),
  ], scheme: _baseUri.scheme == 'https' ? 'wss' : 'ws');

  @override
  Future<void> register(InteractiveSessionDescriptor descriptor) => _send(
    'POST',
    ['v1', 'sessions'],
    body: descriptor.toJson(),
    expectedStatus: 201,
  );

  @override
  Future<void> ready(String sessionId) => _send('POST', [
    'v1',
    'sessions',
    _segment(sessionId),
    'ready',
  ], expectedStatus: 202);

  @override
  Future<void> discard(String sessionId) => _send('DELETE', [
    'v1',
    'sessions',
    _segment(sessionId),
  ], expectedStatus: 204);

  @override
  Future<void> update(InteractiveSessionDescriptor descriptor) => _send(
    'PUT',
    ['v1', 'sessions', _segment(descriptor.id)],
    body: descriptor.toJson(),
    expectedStatus: 200,
  );

  @override
  Future<void> rotateParticipant(
    String sessionId,
    String subject,
    int generation,
  ) => _send(
    'PUT',
    ['v1', 'sessions', _segment(sessionId), 'participants', _segment(subject)],
    body: {'generation': generation},
    expectedStatus: 200,
  );

  @override
  Future<void> end(String sessionId) => _send('POST', [
    'v1',
    'sessions',
    _segment(sessionId),
    'end',
  ], expectedStatus: 202);

  Future<void> _send(
    String method,
    List<String> segments, {
    Map<String, Object?>? body,
    required int expectedStatus,
  }) async {
    final request = http.Request(method, _uri(segments))
      ..headers.addAll({
        'content-type': 'application/json',
        'x-ii-relay-control': _controlSecret,
      });
    if (body != null) request.body = jsonEncode(body);
    late http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
    } on Object {
      throw const ApiError(
        503,
        'interactive_relay_unavailable',
        'The interactive session relay is unavailable.',
      );
    }
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != expectedStatus) {
      throw ApiError(
        502,
        'interactive_relay_rejected',
        'The interactive session relay rejected the control request.',
        details: {'status': response.statusCode},
      );
    }
  }

  Uri _uri(List<String> segments, {String? scheme}) => _baseUri.replace(
    scheme: scheme,
    pathSegments: [
      ..._baseUri.pathSegments.where((item) => item.isNotEmpty),
      ...segments,
    ],
    query: null,
    fragment: null,
  );
}

Uri _validatedBase(Uri value) {
  final local = const {'localhost', '127.0.0.1'}.contains(value.host);
  if (value.host.isEmpty ||
      (value.scheme != 'https' && !(local && value.scheme == 'http')) ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError.value(value, 'baseUri', 'must be an HTTPS origin');
  }
  return value;
}

String _validatedSecret(String value) {
  if (value.length < 32 || value.length > 8192) {
    throw ArgumentError.value(
      value.length,
      'controlSecret',
      'must be 32-8192 characters',
    );
  }
  return value;
}

String _segment(String value) {
  if (value.isEmpty || value.length > 200 || value.contains('/')) {
    throw const FormatException('Invalid relay path identity.');
  }
  return value;
}

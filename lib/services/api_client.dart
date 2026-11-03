import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'client_breadcrumbs.dart';

typedef ApiFailureObserver =
    Future<void> Function(Object error, StackTrace stackTrace, String route);
typedef ApiAuthTokenProvider = Future<String?> Function(bool refresh);

final class ApiFailure implements Exception {
  const ApiFailure(
    this.code,
    this.message, {
    this.statusCode,
    this.details,
    this.requestId,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Object? details;
  final String? requestId;

  @override
  String toString() => message;
}

final class ApiClient {
  ApiClient({
    FirebaseAuth? auth,
    http.Client? httpClient,
    String? baseUrl,
    this.reportFailures = true,
    this._authTokenProvider,
  }) : _providedAuth = auth,
       _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.controlApiBaseUrl;

  static ApiFailureObserver? failureObserver;

  final FirebaseAuth? _providedAuth;
  final ApiAuthTokenProvider? _authTokenProvider;
  final http.Client _http;
  final Uuid _uuid = const Uuid();
  final String _baseUrl;
  final bool reportFailures;

  String get baseUrl => _baseUrl;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  Future<JsonMap> get(String path, {Map<String, String>? query}) {
    return _observe(path, () => _send('GET', path, query: query));
  }

  Future<JsonMap> post(String path, {JsonMap body = const {}}) {
    return _observe(path, () => _send('POST', path, body: body));
  }

  Future<JsonMap> put(String path, {JsonMap body = const {}}) {
    return _observe(path, () => _send('PUT', path, body: body));
  }

  Future<JsonMap> postPublic(String path, {JsonMap body = const {}}) {
    return _observe(
      path,
      () => _send('POST', path, body: body, authenticated: false),
    );
  }

  Future<JsonMap> patch(String path, {JsonMap body = const {}}) {
    return _observe(path, () => _send('PATCH', path, body: body));
  }

  Future<JsonMap> delete(String path, {JsonMap body = const {}}) {
    return _observe(path, () => _send('DELETE', path, body: body));
  }

  Future<void> putBytes(
    Uri uri,
    List<int> bytes, {
    required Map<String, String> headers,
  }) {
    return _observe(
      'direct-asset-write',
      () => _putBytes(uri, bytes, headers: headers),
    );
  }

  Future<Uint8List> getBytes(Uri uri, {required int maxBytes}) {
    return _observe(
      'direct-asset-read',
      () => _getBytes(uri, maxBytes: maxBytes),
    );
  }

  Future<Uint8List> _getBytes(Uri uri, {required int maxBytes}) async {
    if (maxBytes <= 0 || maxBytes > 512 * 1024 * 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'is outside the limit');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['accept'] = 'application/octet-stream';
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (streamed.statusCode != 200) {
      await streamed.stream.listen((_) {}).cancel();
      throw ApiFailure(
        'asset_download_failed',
        'Google Cloud Storage rejected the direct asset download.',
        statusCode: streamed.statusCode,
      );
    }
    final declaredLength = streamed.contentLength;
    if (declaredLength != null && declaredLength > maxBytes) {
      await streamed.stream.listen((_) {}).cancel();
      throw const ApiFailure(
        'asset_download_too_large',
        'The workspace asset is too large for local editing.',
      );
    }

    final iterator = StreamIterator<List<int>>(streamed.stream);
    final output = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    try {
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw const ApiFailure(
            'asset_download_timeout',
            'The direct workspace asset download timed out.',
          );
        }
        final hasNext = await iterator.moveNext().timeout(
          remaining,
          onTimeout: () => throw const ApiFailure(
            'asset_download_timeout',
            'The direct workspace asset download timed out.',
          ),
        );
        if (!hasNext) break;
        final chunk = iterator.current;
        if (output.length + chunk.length > maxBytes) {
          throw const ApiFailure(
            'asset_download_too_large',
            'The workspace asset is too large for local editing.',
          );
        }
        output.add(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    if (declaredLength != null && output.length != declaredLength) {
      throw const ApiFailure(
        'asset_download_incomplete',
        'The direct workspace asset download was incomplete.',
      );
    }
    return output.takeBytes();
  }

  Future<void> _putBytes(
    Uri uri,
    List<int> bytes, {
    required Map<String, String> headers,
  }) async {
    final request = http.Request('PUT', uri)
      ..headers.addAll(headers)
      ..bodyBytes = bytes;
    final streamed = await _http
        .send(request)
        .timeout(const Duration(minutes: 5));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        'asset_upload_failed',
        'Google Cloud Storage rejected the direct asset upload.',
        statusCode: response.statusCode,
      );
    }
  }

  Future<T> _observe<T>(String route, Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      final observer = failureObserver;
      if (reportFailures && observer != null && _shouldReport(error)) {
        unawaited(observer(error, stackTrace, route));
      }
      rethrow;
    }
  }

  Future<JsonMap> _send(
    String method,
    String path, {
    Map<String, String>? query,
    JsonMap? body,
    bool refreshToken = false,
    bool authenticated = true,
  }) async {
    final requestId = _uuid.v4();
    final recordsBreadcrumb = path != 'v1/client-errors';
    if (recordsBreadcrumb) {
      ClientBreadcrumbs.recordGlobal(
        category: 'api',
        name: 'request.started',
        route: path,
        requestId: requestId,
      );
    }
    try {
      final result = await _sendAttempt(
        method,
        path,
        query: query,
        body: body,
        refreshToken: refreshToken,
        authenticated: authenticated,
        requestId: requestId,
      );
      if (recordsBreadcrumb) {
        ClientBreadcrumbs.recordGlobal(
          category: 'api',
          name: 'request.succeeded',
          route: path,
          requestId: requestId,
        );
      }
      return result;
    } on Object catch (error) {
      if (recordsBreadcrumb) {
        ClientBreadcrumbs.recordGlobal(
          category: 'api',
          name: 'request.failed',
          route: path,
          requestId: error is ApiFailure
              ? error.requestId ?? requestId
              : requestId,
          statusCode: error is ApiFailure ? error.statusCode : null,
        );
      }
      rethrow;
    }
  }

  Future<JsonMap> _sendAttempt(
    String method,
    String path, {
    Map<String, String>? query,
    JsonMap? body,
    required bool refreshToken,
    required bool authenticated,
    required String requestId,
  }) async {
    final base = _baseUrl;
    if (base.isEmpty) {
      throw const ApiFailure(
        'data_plane_required',
        'Connect a GCP data plane first.',
      );
    }
    final baseUri = base.startsWith('/')
        ? Uri.base.resolve(base)
        : Uri.parse(base);
    final uri = baseUri.replace(queryParameters: {'route': path, ...?query});
    final request = http.Request(method, uri)
      ..headers.addAll({
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-request-id': requestId,
        'x-ii-os-read-policy': 'explicit-v1',
      });
    if (authenticated) {
      final provider = _authTokenProvider;
      String? token;
      if (provider != null) {
        token = await provider(refreshToken);
      } else {
        final user = _auth.currentUser;
        if (user == null) {
          throw const ApiFailure('unauthenticated', 'Sign in is required.');
        }
        token = await user.getIdToken(refreshToken);
      }
      if (token == null || token.isEmpty) {
        throw const ApiFailure(
          'unauthenticated',
          'Firebase did not return an ID token.',
        );
      }
      request.headers['authorization'] = 'Bearer $token';
    }
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    if (authenticated && response.statusCode == 401 && !refreshToken) {
      return _sendAttempt(
        method,
        path,
        query: query,
        body: body,
        refreshToken: true,
        authenticated: true,
        requestId: requestId,
      );
    }
    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw ApiFailure(
          'invalid_response',
          'The server returned an unreadable response.',
          statusCode: response.statusCode,
          requestId: response.headers['x-request-id'] ?? requestId,
        );
      }
    }
    final json = asJsonMap(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = asJsonMap(json['error']);
      throw ApiFailure(
        error['code'] as String? ?? 'request_failed',
        error['message'] as String? ?? 'The request failed.',
        statusCode: response.statusCode,
        details: error['details'],
        requestId: response.headers['x-request-id'] ?? requestId,
      );
    }
    return json;
  }

  void close() => _http.close();
}

bool _shouldReport(Object error) {
  if (error is! ApiFailure) return true;
  final status = error.statusCode;
  return status == null ||
      status >= 500 ||
      error.code == 'invalid_response' ||
      error.code == 'request_failed';
}

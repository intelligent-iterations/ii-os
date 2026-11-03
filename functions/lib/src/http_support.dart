import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'api_error.dart';

const int maxJsonBodyBytes = 1024 * 1024;

Future<Map<String, Object?>> readJsonObject(Request request) async {
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    if (bytes.length + chunk.length > maxJsonBodyBytes) {
      throw const ApiError(
        413,
        'request_too_large',
        'The request body exceeds 1 MiB.',
      );
    }
    bytes.addAll(chunk);
  }
  if (bytes.isEmpty) return <String, Object?>{};
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object');
    }
    return decoded;
  } on FormatException {
    throw const ApiError(
      400,
      'invalid_json',
      'A valid JSON object is required.',
    );
  }
}

Response jsonResponse(int status, Object? value, {String? requestId}) {
  return Response(
    status,
    body: jsonEncode(value),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-request-id': ?requestId,
    },
  );
}

String requiredString(
  Map<String, Object?> json,
  String key, {
  int maxLength = 500,
}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw ApiError(400, 'invalid_$key', '$key is required.');
  }
  final result = value.trim();
  if (result.length > maxLength) {
    throw ApiError(400, 'invalid_$key', '$key is too long.');
  }
  return result;
}

List<String> stringList(
  Map<String, Object?> json,
  String key, {
  int maxItems = 100,
  int maxItemLength = 300,
}) {
  final raw = json[key];
  if (raw == null) return <String>[];
  if (raw is! List<Object?> || raw.length > maxItems) {
    throw ApiError(400, 'invalid_$key', '$key must be a bounded string list.');
  }
  final result = <String>[];
  for (final value in raw) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > maxItemLength) {
      throw ApiError(400, 'invalid_$key', '$key contains an invalid value.');
    }
    result.add(value.trim());
  }
  return result;
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'client_breadcrumbs.dart';
import 'client_telemetry_sanitizer.dart';

typedef ClientErrorSender = Future<void> Function(JsonMap payload);

final class ClientErrorReporter {
  ClientErrorReporter({
    ApiClient? api,
    this.sender,
    ClientBreadcrumbs? breadcrumbs,
    DateTime Function()? clock,
  }) : _breadcrumbs = breadcrumbs ?? ClientBreadcrumbs.global,
       _clock = clock ?? DateTime.now,
       _api = api ?? ApiClient(reportFailures: false),
       _ownsApi = api == null;

  static ClientErrorReporter? _global;

  final ApiClient _api;
  final bool _ownsApi;
  final ClientErrorSender? sender;
  final ClientBreadcrumbs? _breadcrumbs;
  final DateTime Function() _clock;
  final Map<String, DateTime> _recent = {};

  static void install(ClientErrorReporter reporter) {
    _global = reporter;
  }

  static Future<void> reportGlobal(
    Object error,
    StackTrace stackTrace, {
    required String source,
    String? workspaceId,
    String? route,
  }) async {
    await _global?.report(
      error,
      stackTrace,
      source: source,
      workspaceId: workspaceId,
      route: route,
    );
  }

  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    required String source,
    String? workspaceId,
    String? route,
  }) async {
    if (!_shouldReport(error)) return;
    final now = _clock().toUtc();
    final safeRoute = sanitizeClientTelemetryRoute(route ?? Uri.base.path);
    final resolvedWorkspaceId = workspaceId?.trim().isNotEmpty == true
        ? workspaceId!.trim()
        : telemetryWorkspaceId(safeRoute);
    final relatedRequestId = error is ApiFailure ? error.requestId : null;
    final payload = <String, Object?>{
      'schemaVersion': 'ii-os.error.v2',
      'occurredAt': now.toIso8601String(),
      'source': boundClientTelemetry(source, 80),
      'errorType': boundClientTelemetry(
        error is ApiFailure ? error.code : error.runtimeType.toString(),
        120,
      ),
      'message': redactClientTelemetry(error.toString(), 1200),
      'stackTrace': redactClientTelemetry(stackTrace.toString(), 5000),
      'route': safeRoute,
      if (resolvedWorkspaceId != null)
        'workspaceId': boundClientTelemetry(resolvedWorkspaceId, 120),
      if (relatedRequestId?.isNotEmpty == true)
        'relatedRequestId': boundClientTelemetry(relatedRequestId!, 100),
      'breadcrumbs': _breadcrumbs?.snapshot() ?? const <JsonMap>[],
    };
    final fingerprint =
        '${payload['source']}|${payload['errorType']}|'
        '${payload['message']}|${payload['route']}';
    final previous = _recent[fingerprint];
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 1)) {
      return;
    }
    _recent
      ..removeWhere(
        (key, seenAt) => now.difference(seenAt) >= const Duration(minutes: 5),
      )
      ..[fingerprint] = now;

    debugPrint(
      jsonEncode({
        'severity': 'ERROR',
        'message': 'ii-os client error captured',
        'event': {
          'schemaVersion': 'ii-os.error.v2',
          'source': payload['source'],
          'errorType': payload['errorType'],
        },
      }),
    );
    try {
      final configuredSender = sender;
      if (configuredSender != null) {
        await configuredSender(payload);
      } else {
        await _api.post('v1/client-errors', body: payload);
      }
    } on Object catch (reportingError) {
      debugPrint(
        jsonEncode({
          'severity': 'ERROR',
          'message': 'ii-os client error reporting failed',
          'errorType': reportingError.runtimeType.toString(),
        }),
      );
    }
  }

  void close() {
    if (_ownsApi) _api.close();
  }
}

bool _shouldReport(Object error) {
  if (error is! ApiFailure) return true;
  final status = error.statusCode;
  return status == null ||
      status >= 500 ||
      error.code == 'invalid_response' ||
      error.code == 'request_failed';
}

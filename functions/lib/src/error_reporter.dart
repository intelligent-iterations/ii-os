import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'api_error.dart';

const String errorEventSchema = 'ii-os.error.v2';
const int maximumErrorBreadcrumbs = 30;
const Duration maximumClientErrorAge = Duration(minutes: 15);

abstract interface class ErrorEventSink {
  Future<void> write(ErrorRecord record);
}

final class ErrorBreadcrumb {
  const ErrorBreadcrumb({
    required this.occurredAt,
    required this.category,
    required this.name,
    this.route,
    this.requestId,
    this.statusCode,
  });

  static const _categories = {'navigation', 'api'};
  static final _namePattern = RegExp(r'^[a-z][a-z0-9._-]{0,79}$');

  final DateTime occurredAt;
  final String category;
  final String name;
  final String? route;
  final String? requestId;
  final int? statusCode;

  static List<ErrorBreadcrumb> parseList(
    Object? value, {
    required DateTime now,
  }) {
    if (value == null) return const [];
    if (value is! List<Object?> || value.length > maximumErrorBreadcrumbs) {
      throw const ApiError(
        400,
        'invalid_client_error_breadcrumbs',
        'Client error breadcrumbs are invalid.',
      );
    }
    return [for (final entry in value) _parse(entry, now: now)];
  }

  static ErrorBreadcrumb _parse(Object? value, {required DateTime now}) {
    if (value is! Map) return _invalid();
    final data = value.cast<Object?, Object?>();
    final occurredAt = DateTime.tryParse(data['occurredAt']?.toString() ?? '');
    final category = data['category'];
    final name = data['name'];
    final statusCode = data['statusCode'];
    if (occurredAt == null ||
        !_clientTimeAllowed(occurredAt, now) ||
        category is! String ||
        !_categories.contains(category) ||
        name is! String ||
        !_namePattern.hasMatch(name) ||
        (statusCode != null &&
            (statusCode is! int || statusCode < 100 || statusCode > 599))) {
      return _invalid();
    }
    final route = _optionalBounded(data['route'], 300, route: true);
    final requestId = _optionalBounded(data['requestId'], 100);
    return ErrorBreadcrumb(
      occurredAt: occurredAt.toUtc(),
      category: category,
      name: name,
      route: route,
      requestId: requestId,
      statusCode: statusCode as int?,
    );
  }

  static Never _invalid() => throw const ApiError(
    400,
    'invalid_client_error_breadcrumbs',
    'Client error breadcrumbs are invalid.',
  );

  Map<String, Object?> toJson() => {
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'category': category,
    'name': name,
    if (route != null) 'route': route,
    if (requestId != null) 'requestId': requestId,
    if (statusCode != null) 'statusCode': statusCode,
  };
}

DateTime parseClientErrorOccurredAt(Object? value, {required DateTime now}) {
  if (value == null) return now.toUtc();
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !_clientTimeAllowed(parsed, now)) {
    throw const ApiError(
      400,
      'invalid_client_error_time',
      'Client error time is invalid.',
    );
  }
  return parsed.toUtc();
}

bool _clientTimeAllowed(DateTime value, DateTime now) {
  final utc = value.toUtc();
  final current = now.toUtc();
  return !utc.isBefore(current.subtract(maximumClientErrorAge)) &&
      !utc.isAfter(current.add(const Duration(minutes: 2)));
}

final class ErrorEvent {
  const ErrorEvent({
    required this.source,
    required this.errorType,
    required this.message,
    required this.stackTrace,
    required this.requestId,
    required this.route,
    this.occurredAt,
    this.relatedRequestId,
    this.breadcrumbs = const [],
    this.workspaceId,
    this.actorUid,
  });

  final String source;
  final String errorType;
  final String message;
  final String stackTrace;
  final String requestId;
  final String route;
  final DateTime? occurredAt;
  final String? relatedRequestId;
  final List<ErrorBreadcrumb> breadcrumbs;
  final String? workspaceId;
  final String? actorUid;
}

final class ErrorRecord {
  const ErrorRecord({
    required this.schemaVersion,
    required this.occurredAt,
    required this.receivedAt,
    required this.environment,
    required this.source,
    required this.errorType,
    required this.errorMessage,
    required this.stackTrace,
    required this.requestId,
    required this.breadcrumbs,
    this.relatedRequestId,
    this.route,
    this.workspaceId,
    this.actorKey,
  });

  final String schemaVersion;
  final DateTime occurredAt;
  final DateTime receivedAt;
  final String environment;
  final String source;
  final String errorType;
  final String errorMessage;
  final String stackTrace;
  final String requestId;
  final String? relatedRequestId;
  final String? route;
  final String? workspaceId;
  final String? actorKey;
  final List<ErrorBreadcrumb> breadcrumbs;
}

final class ErrorReporter {
  ErrorReporter({
    required this.environment,
    this.sink,
    void Function(String)? log,
    DateTime Function()? clock,
    this.maximumSinkWritesPerMinute = 5,
    this.sinkTimeout = const Duration(seconds: 3),
  }) : _log = log ?? print,
       _clock = clock ?? DateTime.now {
    if (maximumSinkWritesPerMinute < 1) {
      throw ArgumentError.value(
        maximumSinkWritesPerMinute,
        'maximumSinkWritesPerMinute',
      );
    }
    if (sinkTimeout <= Duration.zero) {
      throw ArgumentError.value(sinkTimeout, 'sinkTimeout');
    }
  }

  final String environment;
  final ErrorEventSink? sink;
  final void Function(String) _log;
  final DateTime Function() _clock;
  final int maximumSinkWritesPerMinute;
  final Duration sinkTimeout;
  DateTime? _sinkWindowStartedAt;
  int _sinkWrites = 0;
  bool _sinkRateLimitLogged = false;

  Future<void> report(ErrorEvent event) async {
    final record = _normalized(event, environment: environment, now: _clock());
    _log(
      jsonEncode({
        'severity': 'ERROR',
        'message': 'ii-os error captured',
        'serviceContext': {'service': 'ii-os', 'version': environment},
        'event': {
          'schemaVersion': record.schemaVersion,
          'source': record.source,
          'errorType': record.errorType,
          'requestId': record.requestId,
        },
      }),
    );
    final configuredSink = sink;
    if (configuredSink == null) return;
    if (!_claimSinkWrite(record.receivedAt)) {
      if (!_sinkRateLimitLogged) {
        _sinkRateLimitLogged = true;
        _log(
          jsonEncode({
            'severity': 'WARNING',
            'message': 'ii-os error sink rate limited',
            'serviceContext': {'service': 'ii-os', 'version': environment},
            'event': {
              'schemaVersion': errorEventSchema,
              'source': 'error.sink',
              'errorType': 'write_rate_limited',
            },
          }),
        );
      }
      return;
    }
    try {
      await configuredSink.write(record).timeout(sinkTimeout);
    } on Object {
      _log(
        jsonEncode({
          'severity': 'ERROR',
          'message': 'ii-os error sink unavailable',
          'serviceContext': {'service': 'ii-os', 'version': environment},
          'event': {
            'schemaVersion': errorEventSchema,
            'source': 'error.sink',
            'errorType': 'write_failed',
            'requestId': record.requestId,
          },
        }),
      );
    }
  }

  bool _claimSinkWrite(DateTime now) {
    final startedAt = _sinkWindowStartedAt;
    if (startedAt == null ||
        now.difference(startedAt) >= const Duration(minutes: 1)) {
      _sinkWindowStartedAt = now;
      _sinkWrites = 0;
      _sinkRateLimitLogged = false;
    }
    if (_sinkWrites >= maximumSinkWritesPerMinute) return false;
    _sinkWrites += 1;
    return true;
  }
}

ErrorRecord _normalized(
  ErrorEvent event, {
  required String environment,
  required DateTime now,
}) {
  final receivedAt = now.toUtc();
  final actorUid = _optional(event.actorUid, 128);
  return ErrorRecord(
    schemaVersion: errorEventSchema,
    occurredAt: (event.occurredAt ?? receivedAt).toUtc(),
    receivedAt: receivedAt,
    environment: _redact(environment, 120),
    source: _redact(event.source, 80),
    errorType: _redact(event.errorType, 120),
    errorMessage: _redact(event.message, 1200),
    stackTrace: _redact(event.stackTrace, 5000),
    requestId: _redact(event.requestId, 100),
    relatedRequestId: _optional(event.relatedRequestId, 100),
    route: _optional(event.route.split('?').first, 300),
    workspaceId: _optional(event.workspaceId, 120),
    actorKey: actorUid == null
        ? null
        : sha256.convert(utf8.encode('$environment:$actorUid')).toString(),
    breadcrumbs: [
      for (final breadcrumb in event.breadcrumbs.take(maximumErrorBreadcrumbs))
        ErrorBreadcrumb(
          occurredAt: breadcrumb.occurredAt.toUtc(),
          category: _redact(breadcrumb.category, 16),
          name: _redact(breadcrumb.name, 80),
          route: _optional(breadcrumb.route?.split('?').first, 300),
          requestId: _optional(breadcrumb.requestId, 100),
          statusCode: breadcrumb.statusCode,
        ),
    ],
  );
}

String? _optional(Object? value, int maxLength) {
  if (value == null) return null;
  final normalized = _redact(value.toString(), maxLength);
  return normalized.isEmpty ? null : normalized;
}

String? _optionalBounded(Object? value, int maxLength, {bool route = false}) {
  if (value == null) return null;
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > maxLength * 2) {
    ErrorBreadcrumb._invalid();
  }
  final normalized = route ? value.split(RegExp(r'[?#]')).first : value;
  return _redact(normalized, maxLength);
}

String _redact(String value, int maxLength) {
  var result = value
      .replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer [REDACTED]',
      )
      .replaceAllMapped(
        RegExp(
          r'(["\x27]?(?:token|secret|password|api[_-]?key)["\x27]?\s*[:=]\s*)["\x27]?([^\s,"\x27}&]+)',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}[REDACTED]',
      )
      .replaceAllMapped(
        RegExp(
          r'(x-goog-(?:signature|credential|security-token)|signature|credential)=([^\s&]+)',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}=[REDACTED]',
      )
      .replaceAll(
        RegExp(r'https://hooks\.slack\.com/services/[^\s]+'),
        'https://hooks.slack.com/services/[REDACTED]',
      )
      .replaceAllMapped(
        RegExp(r'https?://[^\s?#]+(?:[?#][^\s]*)?'),
        (match) => match.group(0)!.split(RegExp(r'[?#]')).first,
      )
      .replaceAll(
        RegExp(
          r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
          caseSensitive: false,
        ),
        '[REDACTED_EMAIL]',
      )
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');
  result = result.trim();
  return _bounded(result, maxLength);
}

String _bounded(String value, int maxLength) => value.length <= maxLength
    ? value
    : '${value.substring(0, maxLength - 3)}...';

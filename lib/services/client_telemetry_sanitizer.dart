String redactClientTelemetry(String value, int maxLength) {
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
  return boundClientTelemetry(result, maxLength);
}

String sanitizeClientTelemetryRoute(String value, {int maxLength = 300}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final withoutQuery = trimmed.split(RegExp(r'[?#]')).first;
  return redactClientTelemetry(withoutQuery, maxLength);
}

String boundClientTelemetry(String value, int maxLength) {
  if (maxLength < 4) throw ArgumentError.value(maxLength, 'maxLength');
  return value.length <= maxLength
      ? value
      : '${value.substring(0, maxLength - 3)}...';
}

String? telemetryWorkspaceId(String route) {
  final normalized = sanitizeClientTelemetryRoute(route);
  final match = RegExp(
    r'(?:^|/)v1/workspaces/([^/]+)|^/workspaces/([^/]+)',
  ).firstMatch(normalized);
  final value = match?.group(1) ?? match?.group(2);
  return value == null || value.isEmpty
      ? null
      : boundClientTelemetry(value, 120);
}

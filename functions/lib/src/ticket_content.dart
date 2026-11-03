import 'dart:convert';

import 'api_error.dart';

const String ticketBodyMarker = '<!-- ii-os-ticket:v1 -->';

final class TicketContent {
  const TicketContent({
    required this.definitionOfDone,
    required this.howToTest,
    required this.permissionProfile,
    required this.permissionRef,
    required this.context,
    required this.structured,
    this.agentReady = false,
  });

  factory TicketContent.fromRequest(Map<String, Object?> request) {
    final permissions = _map(request['permissions']);
    return TicketContent(
      definitionOfDone: _requiredText(
        request['definitionOfDone'],
        'Definition of Done',
        maxLength: 12000,
      ),
      howToTest: _requiredText(
        request['howToTest'],
        'How to test',
        maxLength: 12000,
      ),
      permissionProfile: _safeName(
        permissions['profile'],
        'permission profile',
      ),
      permissionRef: _safeRef(permissions['ref'] ?? 'dev'),
      context: _optionalText(request['context'], maxLength: 30000),
      structured: true,
      agentReady: _agentReady(request['agent']),
    );
  }

  factory TicketContent.parse(Object? rawBody) {
    final body = rawBody is String ? rawBody.trim() : '';
    if (!body.contains(ticketBodyMarker)) {
      return TicketContent(
        definitionOfDone: '',
        howToTest: '',
        permissionProfile: 'none',
        permissionRef: 'dev',
        context: body,
        structured: false,
        agentReady: false,
      );
    }
    final permissionsText = _section(body, 'Permissions');
    var profile = 'none';
    var ref = 'dev';
    var agentReady = false;
    try {
      final decoded = jsonDecode(_withoutFence(permissionsText));
      final permissions = _map(decoded);
      final rawProfile = permissions['profile'];
      final rawRef = permissions['ref'];
      if (rawProfile is String && _safeNamePattern.hasMatch(rawProfile)) {
        profile = rawProfile;
      }
      if (rawRef is String && _safeRefPattern.hasMatch(rawRef)) ref = rawRef;
    } on Object {
      // Malformed content fails closed to the no-agent profile.
    }
    try {
      final decoded = jsonDecode(_withoutFence(_section(body, 'Agent Pickup')));
      agentReady = _agentReady(decoded);
    } on Object {
      // Missing or malformed activation fails closed to human deployment.
    }
    return TicketContent(
      definitionOfDone: _section(body, 'Definition of Done'),
      howToTest: _section(body, 'How to Test'),
      permissionProfile: profile,
      permissionRef: ref,
      context: _section(body, 'Additional Context'),
      structured: true,
      agentReady: agentReady,
    );
  }

  final String definitionOfDone;
  final String howToTest;
  final String permissionProfile;
  final String permissionRef;
  final String context;
  final bool structured;
  final bool agentReady;

  TicketContent withAgentReady(bool ready) => TicketContent(
    definitionOfDone: definitionOfDone,
    howToTest: howToTest,
    permissionProfile: permissionProfile,
    permissionRef: permissionRef,
    context: context,
    structured: structured,
    agentReady: ready,
  );

  String toMarkdown() {
    final permissions = const JsonEncoder.withIndent(
      '  ',
    ).convert({'profile': permissionProfile, 'ref': permissionRef});
    final agent = const JsonEncoder.withIndent(
      '  ',
    ).convert({'ready': agentReady});
    return [
      ticketBodyMarker,
      '',
      '## Definition of Done',
      definitionOfDone,
      '',
      '## How to Test',
      howToTest,
      '',
      '## Permissions',
      '```json',
      permissions,
      '```',
      '',
      '## Agent Pickup',
      '```json',
      agent,
      '```',
      if (context.isNotEmpty) ...['', '## Additional Context', context],
    ].join('\n').trim();
  }

  Map<String, Object?> toJson() => {
    'definitionOfDone': definitionOfDone,
    'howToTest': howToTest,
    'permissions': {'profile': permissionProfile, 'ref': permissionRef},
    'agent': {'ready': agentReady},
    'context': context,
    'structured': structured,
  };
}

bool _agentReady(Object? value) {
  if (value == null) return false;
  final agent = _map(value);
  final ready = agent['ready'];
  if (ready is! bool) {
    throw const ApiError(
      400,
      'ticket_agent_activation_invalid',
      'Agent deployment must be explicitly started or cancelled.',
    );
  }
  return ready;
}

final RegExp _safeNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _safeRefPattern = RegExp(
  r'^(?!/)(?!.*(?:\.\.|//))[A-Za-z0-9._/-]{1,200}$',
);

String _requiredText(Object? value, String label, {required int maxLength}) {
  final result = _optionalText(value, maxLength: maxLength);
  if (result.isEmpty) {
    throw ApiError(
      400,
      'ticket_field_required',
      '$label is required for every ticket.',
    );
  }
  return result;
}

String _optionalText(Object? value, {required int maxLength}) {
  if (value == null) return '';
  if (value is! String || value.length > maxLength) {
    throw const ApiError(
      400,
      'ticket_field_invalid',
      'A ticket field is invalid or too long.',
    );
  }
  return value.trim();
}

String _safeName(Object? value, String label) {
  if (value is! String || !_safeNamePattern.hasMatch(value)) {
    throw ApiError(400, 'ticket_permissions_invalid', 'Select a valid $label.');
  }
  return value;
}

String _safeRef(Object? value) {
  if (value is! String || !_safeRefPattern.hasMatch(value)) {
    throw const ApiError(
      400,
      'ticket_permissions_invalid',
      'Select a valid permission template branch or ref.',
    );
  }
  return value;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw const ApiError(
    400,
    'ticket_permissions_invalid',
    'Ticket permissions must be a JSON object.',
  );
}

String _section(String body, String title) {
  final heading = '## $title';
  final start = body.indexOf(heading);
  if (start < 0) return '';
  final contentStart = start + heading.length;
  final next = body.indexOf('\n## ', contentStart);
  return body.substring(contentStart, next < 0 ? body.length : next).trim();
}

String _withoutFence(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  final firstLine = trimmed.indexOf('\n');
  final lastFence = trimmed.lastIndexOf('```');
  if (firstLine < 0 || lastFence <= firstLine) return trimmed;
  return trimmed.substring(firstLine + 1, lastFence).trim();
}

import 'dart:convert';
import 'dart:typed_data';

enum UiActionKind { activate, type, select, scroll, navigate, waitFor }

extension UiActionKindWire on UiActionKind {
  String get wireName => switch (this) {
    UiActionKind.waitFor => 'wait_for',
    _ => name,
  };

  static UiActionKind parse(String value) => UiActionKind.values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw FormatException('Unknown UI action: $value'),
  );
}

final class UiSemanticNode {
  const UiSemanticNode({
    required this.id,
    required this.role,
    required this.label,
    this.value = '',
    this.enabled = true,
    this.visible = true,
    this.sensitive = false,
  });

  factory UiSemanticNode.fromJson(Map<String, Object?> json) => UiSemanticNode(
    id: _required(json, 'id'),
    role: _required(json, 'role'),
    label: _required(json, 'label'),
    value: json['value']?.toString() ?? '',
    enabled: json['enabled'] != false,
    visible: json['visible'] != false,
    sensitive: json['sensitive'] == true,
  );

  final String id;
  final String role;
  final String label;
  final String value;
  final bool enabled;
  final bool visible;
  final bool sensitive;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'label': label,
    if (value.isNotEmpty) 'value': sensitive ? '[redacted]' : value,
    'enabled': enabled,
    'visible': visible,
    if (sensitive) 'sensitive': true,
  };
}

final class UiSemanticSnapshot {
  const UiSemanticSnapshot({
    required this.revision,
    required this.route,
    required this.nodes,
    this.focusId = '',
    this.modalId = '',
  });

  factory UiSemanticSnapshot.fromJson(Map<String, Object?> json) {
    final rawNodes = json['nodes'];
    if (rawNodes is! List<Object?>) {
      throw const FormatException('nodes must be a list');
    }
    return UiSemanticSnapshot(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      route: _required(json, 'route'),
      focusId: json['focusId']?.toString() ?? '',
      modalId: json['modalId']?.toString() ?? '',
      nodes: rawNodes
          .whereType<Map>()
          .map((item) => UiSemanticNode.fromJson(item.cast<String, Object?>()))
          .toList(),
    );
  }

  final int revision;
  final String route;
  final String focusId;
  final String modalId;
  final List<UiSemanticNode> nodes;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'route': route,
    if (focusId.isNotEmpty) 'focusId': focusId,
    if (modalId.isNotEmpty) 'modalId': modalId,
    'nodes': nodes
        .where((item) => item.visible)
        .map((item) => item.toJson())
        .toList(),
  };
}

final class UiActionRequest {
  const UiActionRequest({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.expectedRevision,
    this.value = '',
  });

  factory UiActionRequest.fromFrame(String id, Map<String, Object?> payload) =>
      UiActionRequest(
        id: id,
        kind: UiActionKindWire.parse(_required(payload, 'action')),
        targetId: _required(payload, 'target'),
        expectedRevision: (payload['expectedRevision'] as num?)?.toInt() ?? 0,
        value: payload['value']?.toString() ?? '',
      );

  final String id;
  final UiActionKind kind;
  final String targetId;
  final int expectedRevision;
  final String value;
}

final class UiScreenshot {
  const UiScreenshot({
    required this.revision,
    required this.mimeType,
    required this.bytes,
    required this.redacted,
  });

  factory UiScreenshot.fromJson(
    Map<String, Object?> json, {
    required int maxBytes,
  }) {
    if (json['encoding'] != 'base64' || json['bytes'] is! String) {
      throw const FormatException('Screenshot must use base64.');
    }
    final bytes = base64Decode(json['bytes']! as String);
    if (bytes.length > maxBytes) {
      throw const FormatException('Screenshot exceeds the byte limit.');
    }
    return UiScreenshot(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      mimeType: _required(json, 'mimeType'),
      bytes: Uint8List.fromList(bytes),
      redacted: json['redacted'] == true,
    );
  }

  final int revision;
  final String mimeType;
  final Uint8List bytes;
  final bool redacted;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'mimeType': mimeType,
    'encoding': 'base64',
    'bytes': base64Encode(bytes),
    'redacted': redacted,
  };
}

String _required(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 512) {
    throw FormatException('$key is invalid');
  }
  return value.trim();
}

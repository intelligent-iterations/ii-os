import 'dart:convert';
import 'dart:typed_data';

import 'protocol.dart';

final class SessionFrame {
  const SessionFrame({
    required this.type,
    required this.id,
    required this.payload,
    this.sequence,
  });

  factory SessionFrame.fromJson(Map<String, Object?> json) {
    if (json['v'] != interactiveSessionProtocolVersion) {
      throw const FormatException('Unsupported interactive session protocol.');
    }
    final type = json['type'];
    final id = json['id'];
    final payload = json['payload'];
    if (type is! String ||
        type.isEmpty ||
        id is! String ||
        id.isEmpty ||
        payload is! Map) {
      throw const FormatException('Invalid session frame.');
    }
    return SessionFrame(
      type: type,
      id: id,
      sequence: (json['sequence'] as num?)?.toInt(),
      payload: payload.cast<String, Object?>(),
    );
  }

  final String type;
  final String id;
  final int? sequence;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'v': interactiveSessionProtocolVersion,
    'type': type,
    'id': id,
    if (sequence != null) 'sequence': sequence,
    'payload': payload,
  };

  String encode() => jsonEncode(toJson());

  static SessionFrame decode(String value, {int maxBytes = 64 * 1024}) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Session frame exceeds the byte limit.');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Frame must be an object.');
    }
    return SessionFrame.fromJson(decoded.cast<String, Object?>());
  }
}

Map<String, Object?> terminalBytes(Uint8List bytes) => {
  'encoding': 'base64',
  'bytes': base64Encode(bytes),
};

Uint8List parseTerminalBytes(Map<String, Object?> payload, int maxBytes) {
  if (payload['encoding'] != 'base64' || payload['bytes'] is! String) {
    throw const FormatException('Terminal bytes must use base64.');
  }
  final bytes = base64Decode(payload['bytes']! as String);
  if (bytes.length > maxBytes) {
    throw const FormatException('Terminal payload exceeds the byte limit.');
  }
  return bytes;
}

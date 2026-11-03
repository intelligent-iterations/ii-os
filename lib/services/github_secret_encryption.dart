import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/x25519.dart' show PublicKey, SealedBox;

String encryptGitHubSecret({
  required String publicKey,
  required List<int> plaintext,
}) {
  final keyBytes = base64Decode(publicKey);
  if (keyBytes.length != 32) {
    throw const FormatException('GitHub returned an invalid encryption key.');
  }
  final sealed = SealedBox(
    PublicKey(Uint8List.fromList(keyBytes)),
  ).encrypt(Uint8List.fromList(plaintext));
  return base64Encode(sealed);
}

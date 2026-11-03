import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/github_secret_encryption.dart';
import 'package:pinenacl/x25519.dart' show PrivateKey, SealedBox;

void main() {
  test('GitHub secret sealed-box encryption is interoperable', () {
    final privateKey = PrivateKey.generate();
    final plaintext = Uint8List.fromList(utf8.encode('[{"name":"cookie"}]'));
    final encrypted = encryptGitHubSecret(
      publicKey: base64Encode(Uint8List.fromList(privateKey.publicKey)),
      plaintext: plaintext,
    );
    final decrypted = SealedBox(
      privateKey,
    ).decrypt(Uint8List.fromList(base64Decode(encrypted)));
    expect(utf8.decode(decrypted), utf8.decode(plaintext));
    expect(base64Decode(encrypted).length, plaintext.length + 48);
  });

  test('GitHub secret encryption rejects malformed public keys', () {
    expect(
      () => encryptGitHubSecret(
        publicKey: base64Encode(const [1, 2, 3]),
        plaintext: const [4],
      ),
      throwsFormatException,
    );
  });
}

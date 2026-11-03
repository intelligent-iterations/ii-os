import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Seals a workspace's DeepSeek key for storage in Firestore.
///
/// The other credentials ii-os holds are verified rather than replayed, so they
/// are stored as HMAC digests and never recovered. This one has to be sent to
/// DeepSeek on every enhancement, so it has to be recoverable -- which makes
/// encryption at rest the control that matters, and makes the key-encryption
/// key the thing that must not live beside the ciphertext.
///
/// Version 2 uses a dedicated deployment secret as its root key. Version 1
/// derived its key from the workflow-token pepper; it remains readable so
/// existing workspace credentials can be opened and re-sealed under version 2
/// without being discarded.
final class PromptEnhancementKeyCodec {
  PromptEnhancementKeyCodec({
    required String encryptionKey,
    String legacyPepper = '',
  }) : _encryptionKey = utf8.encode(encryptionKey),
       _legacyPepper = utf8.encode(legacyPepper);

  static const int currentVersion = 2;
  static const int legacyVersion = 1;

  static final List<int> _legacyInfo = utf8.encode(
    'ii-os/prompt-enhancement/key/v1',
  );
  static final List<int> _currentInfo = utf8.encode(
    'ii-os/prompt-enhancement/key/v2',
  );

  final List<int> _encryptionKey;
  final List<int> _legacyPepper;
  final AesGcm _algorithm = AesGcm.with256bits();

  /// False when the dedicated root key is absent or too short to derive from.
  bool get isConfigured => _encryptionKey.length >= 32;

  bool needsMigration(Map<String, Object?> sealed) =>
      sealed['version'] == legacyVersion;

  /// Encrypts [apiKey] under a key derived for [workspaceId].
  ///
  /// The workspace id is both the HKDF salt and the AEAD associated data, so a
  /// sealed key lifted from one workspace document cannot be opened in another.
  Future<Map<String, Object?>> seal({
    required String workspaceId,
    required String apiKey,
  }) async {
    final box = await _algorithm.encrypt(
      utf8.encode(apiKey),
      secretKey: await _derive(
        rootKey: _encryptionKey,
        workspaceId: workspaceId,
        info: _currentInfo,
      ),
      aad: utf8.encode(workspaceId),
    );
    return {
      'version': currentVersion,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'last4': lastFour(apiKey),
    };
  }

  /// Recovers the key, or null when the record is unreadable.
  ///
  /// Null rather than a throw for a bad MAC or a truncated field: an
  /// unreadable record and an absent one leave the caller in the same place,
  /// and enhancement is designed to fall back to the original prompt either
  /// way.
  Future<String?> open({
    required String workspaceId,
    required Map<String, Object?> sealed,
  }) async {
    final version = sealed['version'];
    final (rootKey, info) = switch (version) {
      currentVersion => (_encryptionKey, _currentInfo),
      legacyVersion => (_legacyPepper, _legacyInfo),
      _ => (<int>[], <int>[]),
    };
    if (rootKey.length < 32) return null;
    final nonce = _bytes(sealed['nonce']);
    final cipherText = _bytes(sealed['ciphertext']);
    final mac = _bytes(sealed['mac']);
    if (nonce == null || cipherText == null || mac == null) return null;
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: await _derive(
          rootKey: rootKey,
          workspaceId: workspaceId,
          info: info,
        ),
        aad: utf8.encode(workspaceId),
      );
      return utf8.decode(clear);
    } on Object {
      return null;
    }
  }

  Future<SecretKey> _derive({
    required List<int> rootKey,
    required String workspaceId,
    required List<int> info,
  }) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(rootKey),
    nonce: utf8.encode(workspaceId),
    info: info,
  );

  static List<int>? _bytes(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }
}

/// The tail of a key, for telling one installed credential from another.
String lastFour(String apiKey) {
  final trimmed = apiKey.trim();
  return trimmed.length <= 4 ? '' : trimmed.substring(trimmed.length - 4);
}

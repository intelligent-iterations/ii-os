import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:ii_os_functions/src/prompt_enhancement_key_codec.dart';
import 'package:test/test.dart';

const _encryptionKey = 'a-dedicated-key-long-enough-for-256-bit-encryption';
const _otherEncryptionKey =
    'a-different-dedicated-key-that-is-also-long-enough';
const _legacyPepper = 'the-workflow-token-pepper-used-before-the-key-existed';
const _apiKey = 'sk-deepseek-example-key-0000-a1b2';

void main() {
  test('recovers a sealed key for the workspace that stored it', () async {
    final codec = _codec();

    final sealed = await codec.seal(
      workspaceId: 'workspace-1',
      apiKey: _apiKey,
    );

    expect(sealed['version'], 2);
    expect(
      await codec.open(workspaceId: 'workspace-1', sealed: sealed),
      _apiKey,
    );
    expect(codec.needsMigration(sealed), isFalse);
  });

  test('the stored record never contains the key', () async {
    final codec = _codec();

    final sealed = await codec.seal(
      workspaceId: 'workspace-1',
      apiKey: _apiKey,
    );

    expect(sealed.values.join(' '), isNot(contains(_apiKey)));
    expect(sealed.values.join(' '), isNot(contains('sk-deepseek')));
    expect(sealed['last4'], 'a1b2');
  });

  test('a record lifted into another workspace does not open', () async {
    final codec = _codec();

    final sealed = await codec.seal(
      workspaceId: 'workspace-1',
      apiKey: _apiKey,
    );

    expect(
      await codec.open(workspaceId: 'workspace-2', sealed: sealed),
      isNull,
    );
  });

  test('a record does not open under a different encryption key', () async {
    final sealed = await _codec().seal(
      workspaceId: 'workspace-1',
      apiKey: _apiKey,
    );

    expect(
      await PromptEnhancementKeyCodec(
        encryptionKey: _otherEncryptionKey,
        legacyPepper: _legacyPepper,
      ).open(workspaceId: 'workspace-1', sealed: sealed),
      isNull,
    );
  });

  test('opens a version-1 record with only the legacy pepper', () async {
    final legacy = await _sealLegacy(
      workspaceId: 'workspace-1',
      apiKey: _apiKey,
    );

    expect(
      await _codec().open(workspaceId: 'workspace-1', sealed: legacy),
      _apiKey,
    );
    expect(_codec().needsMigration(legacy), isTrue);
    expect(
      await PromptEnhancementKeyCodec(
        encryptionKey: _encryptionKey,
      ).open(workspaceId: 'workspace-1', sealed: legacy),
      isNull,
    );
  });

  test('a tampered record is refused rather than partially decoded', () async {
    final codec = _codec();
    final sealed = await codec.seal(
      workspaceId: 'workspace-1',
      apiKey: _apiKey,
    );

    for (final field in ['nonce', 'ciphertext', 'mac']) {
      final tampered = {...sealed, field: 'AAAAAAAAAAAAAAAAAAAAAA=='};
      expect(
        await codec.open(workspaceId: 'workspace-1', sealed: tampered),
        isNull,
        reason: field,
      );
    }
    expect(
      await codec.open(
        workspaceId: 'workspace-1',
        sealed: {...sealed, 'version': 99},
      ),
      isNull,
    );
    expect(
      await codec.open(
        workspaceId: 'workspace-1',
        sealed: {...sealed, 'ciphertext': 'not base64!'},
      ),
      isNull,
    );
  });

  test(
    'two seals of one key differ, so ciphertext is not a fingerprint',
    () async {
      final codec = _codec();

      final first = await codec.seal(workspaceId: 'w', apiKey: _apiKey);
      final second = await codec.seal(workspaceId: 'w', apiKey: _apiKey);

      expect(first['ciphertext'], isNot(second['ciphertext']));
      expect(first['nonce'], isNot(second['nonce']));
    },
  );

  test('reports itself unconfigured when the encryption key is too short', () {
    expect(PromptEnhancementKeyCodec(encryptionKey: '').isConfigured, isFalse);
    expect(
      PromptEnhancementKeyCodec(encryptionKey: 'short').isConfigured,
      isFalse,
    );
    expect(_codec().isConfigured, isTrue);
  });

  test('lastFour names a key without revealing it', () {
    expect(lastFour(_apiKey), 'a1b2');
    expect(lastFour('  padded-key-9xyz  '), '9xyz');
    expect(lastFour('abcd'), '');
    expect(lastFour(''), '');
  });
}

PromptEnhancementKeyCodec _codec() => PromptEnhancementKeyCodec(
  encryptionKey: _encryptionKey,
  legacyPepper: _legacyPepper,
);

Future<Map<String, Object?>> _sealLegacy({
  required String workspaceId,
  required String apiKey,
}) async {
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(utf8.encode(_legacyPepper)),
    nonce: utf8.encode(workspaceId),
    info: utf8.encode('ii-os/prompt-enhancement/key/v1'),
  );
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(apiKey),
    secretKey: key,
    aad: utf8.encode(workspaceId),
  );
  return {
    'version': 1,
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
    'last4': lastFour(apiKey),
  };
}

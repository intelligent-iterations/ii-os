import 'package:ii_os_functions/src/workflow_token_codec.dart';
import 'package:test/test.dart';

void main() {
  group('WorkflowTokenCodec', () {
    final codec = WorkflowTokenCodec(
      pepper: List<String>.filled(32, 'p').join(),
      randomBytes: (length) => List<int>.generate(length, (index) => index),
    );
    const tokenId =
        '123e4567-e89b-'
        '12d3-a456-426614174000';

    test('issues a 256-bit opaque token and a keyed digest', () {
      final issued = codec.issue(tokenId);

      expect(codec.isConfigured, isTrue);
      expect(issued.value, startsWith('iiost_v1.$tokenId.'));
      expect(issued.value.split('.').last, hasLength(43));
      expect(issued.digest, hasLength(64));
      expect(issued.digest, isNot(contains(issued.value.split('.').last)));
      expect(codec.matches(issued.digest, issued.value), isTrue);
    });

    test('parses only canonical tokens and rejects tampering', () {
      final issued = codec.issue(tokenId);

      expect(codec.parse(issued.value)?.id, tokenId);
      expect(
        codec.parse('other.$tokenId.${issued.value.split('.').last}'),
        isNull,
      );
      expect(codec.matches(issued.digest, '${issued.value}x'), isFalse);
    });

    test('requires a pepper with at least 256 bits of material', () {
      expect(WorkflowTokenCodec(pepper: 'short').isConfigured, isFalse);
    });
  });
}

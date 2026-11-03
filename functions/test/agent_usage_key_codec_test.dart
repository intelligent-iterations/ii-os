import 'package:ii_os_functions/src/agent_usage_key_codec.dart';
import 'package:test/test.dart';

void main() {
  const id = '12345678-1234-1234-1234-123456789abc';

  test('issues a parseable key while retaining only an HMAC digest', () {
    final codec = AgentUsageKeyCodec(
      pepper: 'pppppppppppppppppppppppppppppppp',
      randomBytes: (length) => List<int>.filled(length, 7),
    );
    final issued = codec.issue(id);

    expect(issued.value, startsWith('${AgentUsageKeyCodec.prefix}.$id.'));
    expect(issued.digest, hasLength(64));
    expect(issued.digest, isNot(contains(issued.value)));
    expect(codec.parse(issued.value)?.id, id);
    expect(codec.matches(issued.digest, issued.value), isTrue);
    expect(codec.matches(issued.digest, '${issued.value}x'), isFalse);
  });

  test('rejects malformed credentials without exposing details', () {
    final codec = AgentUsageKeyCodec(
      pepper: 'pppppppppppppppppppppppppppppppp',
    );
    expect(codec.parse('not-a-key'), isNull);
    expect(codec.parse('${AgentUsageKeyCodec.prefix}.$id.short'), isNull);
  });
}

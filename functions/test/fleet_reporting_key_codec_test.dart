import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ii_os_functions/src/fleet_reporting_key_codec.dart';
import 'package:test/test.dart';

void main() {
  const id = '12345678-1234-1234-1234-123456789abc';
  FleetReportingKeyCodec codec() => FleetReportingKeyCodec(
    randomBytes: (length) => List<int>.filled(length, 7),
  );

  test('issues a parseable credential while retaining only a digest', () {
    final issued = codec().issue(id);

    expect(issued.value, startsWith('${FleetReportingKeyCodec.prefix}.$id.'));
    expect(issued.digest, hasLength(64));
    expect(issued.digest, isNot(contains(issued.value)));
    expect(codec().parse(issued.value)?.id, id);
    expect(codec().matches(issued.digest, issued.value), isTrue);
    expect(codec().matches(issued.digest, '${issued.value}x'), isFalse);
  });

  test('the secret half carries 32 bytes of generator output', () {
    // The entropy is what makes this credential unguessable, and it is the
    // reason no salt or pepper is mixed in. If this ever shrinks, that
    // reasoning stops holding and the hashing needs revisiting.
    final captured = <int>[];
    FleetReportingKeyCodec(
      randomBytes: (length) {
        captured.add(length);
        return List<int>.filled(length, 1);
      },
    ).issue(id);

    expect(captured, [32]);
  });

  test('the digest is a plain SHA-256 of the whole credential', () {
    final issued = codec().issue(id);

    expect(issued.digest, sha256.convert(utf8.encode(issued.value)).toString());
  });

  test('two codecs agree, because there is no instance secret', () {
    // A peppered codec cannot verify a credential another instance issued
    // unless both hold the same pepper. This one has no such state, which is
    // what removes the deployment-time secret.
    final issued = codec().issue(id);
    final other = FleetReportingKeyCodec();

    expect(other.matches(issued.digest, issued.value), isTrue);
  });

  test('refuses a credential shaped like another surface\x27s', () {
    final subject = codec();
    expect(subject.parse('iiosu_v1.$id.${'A' * 43}'), isNull);
    expect(subject.parse('$id.secret'), isNull);
    expect(
      subject.parse('${FleetReportingKeyCodec.prefix}.not-a-uuid.x'),
      isNull,
    );
    expect(subject.parse('${FleetReportingKeyCodec.prefix}.$id.short'), isNull);
    expect(subject.parse('x' * 200), isNull);
  });
}

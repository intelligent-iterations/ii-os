import 'package:ii_os_functions/src/client_error_rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  test('bounds client error ingestion per actor without durable reads', () {
    var now = DateTime.utc(2026, 8, 25, 16);
    final limiter = ClientErrorRateLimiter(
      maxEvents: 2,
      maxGlobalEvents: 3,
      window: const Duration(minutes: 1),
      clock: () => now,
    );

    expect(limiter.allow('actor-1'), isTrue);
    expect(limiter.allow('actor-1'), isTrue);
    expect(limiter.allow('actor-1'), isFalse);
    expect(limiter.allow('actor-2'), isTrue);
    expect(limiter.allow('actor-3'), isFalse);

    now = now.add(const Duration(minutes: 1));
    expect(limiter.allow('actor-1'), isTrue);
  });
}

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/retention.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 12);

  test('enforces an explicit expiry before asynchronous TTL cleanup', () {
    expect(
      recordRetentionExpired({
        'expiresAt': Timestamp.fromDate(
          now.subtract(const Duration(seconds: 1)),
        ),
      }, now: now),
      isTrue,
    );
    expect(
      recordRetentionExpired({
        'expiresAt': Timestamp.fromDate(now.add(const Duration(seconds: 1))),
      }, now: now),
      isFalse,
    );
  });

  test('bounds legacy records from their creation time', () {
    expect(
      recordRetentionExpired({
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 31))),
      }, now: now),
      isTrue,
    );
    expect(
      recordRetentionExpired({
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 29))),
      }, now: now),
      isFalse,
    );
  });

  test('fails closed when no retention timestamp exists', () {
    expect(recordRetentionExpired(const {}, now: now), isTrue);
  });
}

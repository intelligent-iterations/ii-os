import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/job_run_store.dart';
import 'package:test/test.dart';

void main() {
  test('job list cursor round-trips the ordered timestamp and job ID', () {
    final cursor = JobListCursor(
      orderedAt: DateTime.utc(2026, 7, 19, 15, 30, 12, 456),
      jobId: 'job/with spaces',
    );

    final decoded = JobListCursor.decode(cursor.encode());

    expect(decoded.orderedAt, cursor.orderedAt);
    expect(decoded.jobId, cursor.jobId);
  });

  test('job list cursor rejects malformed client input', () {
    expect(
      () => JobListCursor.decode('not-a-cursor'),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_job_cursor',
        ),
      ),
    );
  });
}

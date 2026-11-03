import 'package:ii_os_functions/src/job_run_store.dart';
import 'package:test/test.dart';

void main() {
  group('legacyJobWorkType', () {
    test('recognizes playable content from its artifact metadata', () {
      expect(
        legacyJobWorkType(const {
          'kind': 'custom-output',
          'artifacts': [
            {'content_type': 'video/mp4'},
          ],
        }),
        'content',
      );
    });

    test('recognizes known runtime jobs before they have artifacts', () {
      expect(
        legacyJobWorkType(const {'kind': 'mobile-update-android'}),
        'runtime',
      );
    });

    test('fails closed to other for unclassified legacy jobs', () {
      expect(legacyJobWorkType(const {'kind': 'unknown'}), 'other');
    });
  });
}

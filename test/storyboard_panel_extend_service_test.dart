import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/storyboard_panel_extend_service.dart';

void main() {
  test('extend completion sends the immutable uploaded-frame identity', () {
    final digest = List.filled(64, 'c').join();

    expect(
      storyboardExtendCompletionBody(
        sourcePanelId: 'panel-source',
        jobId: 'job-1',
        sizeBytes: 4096,
        sha256: digest,
      ),
      {
        'sourcePanelId': 'panel-source',
        'jobId': 'job-1',
        'sizeBytes': 4096,
        'sha256': digest,
      },
    );
  });
}

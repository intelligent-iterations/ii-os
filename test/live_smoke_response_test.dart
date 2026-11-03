import 'package:flutter_test/flutter_test.dart';

import '../tool/live_smoke_response.dart';

void main() {
  test('unwraps an object from the audited API data envelope', () {
    final message = liveSmokeAuditedObject({
      'data': {
        'message': {'id': 'message-1', 'status': 'scheduled'},
        'job': {'id': 'job-1'},
      },
    }, 'message');

    expect(message, {'id': 'message-1', 'status': 'scheduled'});
  });

  test('rejects a response without the audited API data envelope', () {
    expect(
      () => liveSmokeAuditedObject({
        'message': {'id': 'message-1'},
      }, 'message'),
      throwsStateError,
    );
  });
}

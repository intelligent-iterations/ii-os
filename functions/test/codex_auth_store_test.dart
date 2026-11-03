import 'package:ii_os_functions/src/codex_auth_store.dart';
import 'package:test/test.dart';

void main() {
  test('saved credentials can enter validation without a device challenge', () {
    expect(codexAuthTransitionAllowed('dispatching', 'validating'), isTrue);
    for (final next in ['writing_secret', 'awaiting_cleanup', 'succeeded']) {
      expect(codexAuthTransitionAllowed('dispatching', next), isFalse);
    }
  });

  test('Codex auth transitions cannot skip live verification', () {
    expect(
      codexAuthTransitionAllowed('dispatching', 'waiting_for_user'),
      isTrue,
    );
    expect(
      codexAuthTransitionAllowed('waiting_for_user', 'validating'),
      isTrue,
    );
    expect(codexAuthTransitionAllowed('validating', 'writing_secret'), isTrue);
    expect(
      codexAuthTransitionAllowed('writing_secret', 'awaiting_cleanup'),
      isTrue,
    );
    expect(codexAuthTransitionAllowed('awaiting_cleanup', 'succeeded'), isTrue);
    expect(codexAuthTransitionAllowed('writing_secret', 'succeeded'), isFalse);

    expect(codexAuthTransitionAllowed('dispatching', 'succeeded'), isFalse);
    expect(
      codexAuthTransitionAllowed('waiting_for_user', 'writing_secret'),
      isFalse,
    );
    expect(codexAuthTransitionAllowed('validating', 'succeeded'), isFalse);
    expect(codexAuthTransitionAllowed('succeeded', 'validating'), isFalse);
  });

  test('failure is permitted from every active stage', () {
    for (final status in const [
      'dispatching',
      'waiting_for_user',
      'validating',
      'writing_secret',
      'awaiting_cleanup',
    ]) {
      expect(
        codexAuthTransitionAllowed(status, 'failed'),
        isTrue,
        reason: status,
      );
    }
  });
}

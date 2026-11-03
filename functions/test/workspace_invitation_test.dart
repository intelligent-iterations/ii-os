import 'package:ii_os_functions/src/workspace_invitation.dart';
import 'package:test/test.dart';

void main() {
  test('validates invitation document IDs without a human-facing token', () {
    expect(isValidInvitationId('11111111-1111-4111-8111-111111111111'), isTrue);
    expect(isValidInvitationId('workspace/invite'), isFalse);
    expect(isValidInvitationId('11111111'), isFalse);
  });

  test('email mismatch directs the person to the invited account', () {
    final error = invitationEmailMismatch(signedInEmail: 'editor@example.com');

    expect(error.status, 403);
    expect(error.code, 'invite_email_mismatch');
    expect(error.message, contains('account that was invited'));
    expect(error.details, {'signedInEmail': 'editor@example.com'});
  });
}

import 'api_error.dart';

final RegExp _invitationIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isValidInvitationId(String value) => _invitationIdPattern.hasMatch(value);

ApiError invitationEmailMismatch({required String signedInEmail}) => ApiError(
  403,
  'invite_email_mismatch',
  'This invitation belongs to a different email address. Sign out and sign '
      'in with the Google or email account that was invited.',
  details: {'signedInEmail': signedInEmail},
);

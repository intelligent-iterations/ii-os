# Passwordless authentication

ii-os accepts Google, Apple, and email one-time-code sessions. Password-based
sign-in remains disabled. An email-code sign-in has three server-side phases:

1. `POST v1/auth/otp/start` creates a 10-minute challenge and sends a six-digit
   code through ZeptoMail using the Secret Manager secret
   `ZEPTOMAIL_API_KEY`.
2. `POST v1/auth/otp/verify` permits at most three guesses. A correct code
   unlocks a two-minute, one-use exchange proof in the challenge record.
3. `POST v1/auth/otp/exchange` consumes that proof and returns a Firebase custom
   token. The client immediately exchanges it for a normal Firebase session.

The database stores HMACs of codes, client bindings, email rate-limit keys, IP
rate-limit keys, and exchange proofs. It never stores a plaintext code or
exchange proof. The client supplies a fresh 256-bit nonce for every send, so a
copied code or exchange proof cannot be used from another sign-in request. The
proof is never placed in a URL, browser history, navigation state, analytics,
or persistent client storage.

## Abuse and lifecycle controls

- Three code guesses per challenge; the third failure makes it stale.
- One send per email per minute, five per email per hour, and twenty per source
  IP per hour.
- Resending supersedes the prior challenge.
- Codes expire after 10 minutes; unlocked exchange proofs expire after 2
  minutes and are consumed atomically.
- Challenge and rate-limit documents use a 24-hour Firestore TTL.
- Browser calls must have the configured ii-os origin. Native calls may omit
  `Origin` and remain protected by the device nonce and server rate limits.
- API sessions must contain either the `ii_os_auth_method=email_otp` claim or
  Firebase's `google.com` or `apple.com` sign-in-provider claim. Password and
  unknown-provider sessions are rejected.

Responses do not reveal whether an account already exists. A Firebase user is
created, or an existing address is marked verified, only after the code has
been proven. This prevents abandoned unverified records.

Email OTP is a single email-possession factor. It is not phishing-resistant
MFA, so sensitive workspace actions still rely on ii-os RBAC and audit controls.
If stronger authentication is required later, add WebAuthn/passkeys as a
separate authenticator rather than increasing OTP lifetime or guess limits.

## Deployment requirements

Each Firebase project that runs ii-os requires enabled versions of
`ZEPTOMAIL_API_KEY`, `II_OS_AUTH_OTP_PEPPER`, and
`II_OS_WORKFLOW_TOKEN_PEPPER`. The function runtime service account needs
Secret Manager access and permission to sign Firebase custom tokens.
`II_OS_AUTH_EMAIL_FROM_ADDRESS` has no default: the API refuses to start until
it is set to an address on a sender domain you have verified in ZeptoMail.

When enabling passwordless sign-in, publish the backend first, then disable
Firebase email/password sign-in and enable and verify the Google and Apple
providers in the Firebase project, and only then publish the UI. This order
prevents the client from exposing a provider that the backend or Firebase
project is not ready to accept.

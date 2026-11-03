# Contributing

Thank you for helping improve ii-os.

## Before opening a change

- Discuss substantial behavior or public API changes with the maintainers.
- Keep deployment-specific identities, credentials, runner labels, paths, and
  operational runbooks out of the repository.
- Use synthetic data in tests, fixtures, examples, and screenshots: generic
  names such as `acme-co`, `example-app`, and `alice@example.com`. Never copy
  production records, real people's accounts or messages, cloud project ids,
  or OAuth client ids into the repository.
- Add or update tests for observable behavior and security boundaries.
- Keep provider-specific behavior behind the owning provider contract.

## Local gate

Run the complete source gate before opening a pull request. It is the same
script continuous integration runs, and it needs no cloud account:

```bash
tool/public_quality_gate.sh
```

If you change UI, also run `flutter test --tags golden` on macOS/arm64, where
the golden screenshots are rendered.

Changes that require real cloud accounts, model providers, signing identities,
or durable user data need separate operator-owned verification. Public pull
requests must remain safe to inspect and test without access to private
infrastructure.

## Security reports

Do not open a public issue for a vulnerability or credential exposure. Follow
the private reporting instructions in `SECURITY.md`.

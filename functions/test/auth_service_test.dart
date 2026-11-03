import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/auth_service.dart';
import 'package:ii_os_functions/src/provider_contracts/identity_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('authenticates through the configured identity provider', () async {
    final identities = _FakeIdentityProvider(_googleIdentity);
    final owners = _FakeSystemOwnerRepository(existing: {'user-1'});
    final service = AuthService(
      identityProvider: identities,
      systemOwners: owners,
      bootstrapOwnerEmails: const {},
    );

    final actor = await service.authenticate(_request('provider-token'));

    expect(identities.tokens, ['provider-token']);
    expect(actor.uid, 'user-1');
    expect(actor.email, 'person@example.com');
    expect(actor.displayName, 'person');
    expect(actor.isOwner, isTrue);
  });

  test('rejects missing bearer credentials before calling a provider', () {
    final identities = _FakeIdentityProvider(_googleIdentity);
    final service = AuthService(
      identityProvider: identities,
      systemOwners: _FakeSystemOwnerRepository(),
      bootstrapOwnerEmails: const {},
    );

    expect(
      () => service.authenticate(
        Request('GET', Uri.parse('https://ii.test/api')),
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(identities.tokens, isEmpty);
  });

  test('rejects an identity method outside the product policy', () {
    final service = AuthService(
      identityProvider: _FakeIdentityProvider(
        const VerifiedIdentity(
          subject: 'user-1',
          email: 'person@example.com',
          emailVerified: true,
          authenticationMethod: AuthenticationMethod.unsupported,
          hasSystemOwnerClaim: false,
        ),
      ),
      systemOwners: _FakeSystemOwnerRepository(),
      bootstrapOwnerEmails: const {},
    );

    expect(
      () => service.authenticate(_request('provider-token')),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'supported_auth_session_required',
        ),
      ),
    );
  });

  test(
    'bootstraps a verified owner without provider-specific authority',
    () async {
      final identities = _FakeIdentityProvider(_googleIdentity);
      final owners = _FakeSystemOwnerRepository();
      final service = AuthService(
        identityProvider: identities,
        systemOwners: owners,
        bootstrapOwnerEmails: const {'person@example.com'},
      );

      final actor = await service.authenticate(_request('provider-token'));

      expect(actor.isOwner, isTrue);
      expect(identities.ownerClaims, ['user-1']);
      expect(owners.grants, [(subject: 'user-1', email: 'person@example.com')]);
    },
  );

  test('does not bootstrap an unverified owner email', () {
    final service = AuthService(
      identityProvider: _FakeIdentityProvider(
        const VerifiedIdentity(
          subject: 'user-1',
          email: 'person@example.com',
          emailVerified: false,
          authenticationMethod: AuthenticationMethod.google,
          hasSystemOwnerClaim: false,
        ),
      ),
      systemOwners: _FakeSystemOwnerRepository(),
      bootstrapOwnerEmails: const {'person@example.com'},
    );

    expect(
      () => service.authenticate(_request('provider-token')),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'owner_email_unverified',
        ),
      ),
    );
  });
}

const _googleIdentity = VerifiedIdentity(
  subject: 'user-1',
  email: 'person@example.com',
  emailVerified: true,
  authenticationMethod: AuthenticationMethod.google,
  hasSystemOwnerClaim: false,
);

Request _request(String token) => Request(
  'GET',
  Uri.parse('https://ii.test/api'),
  headers: {'authorization': 'Bearer $token'},
);

final class _FakeIdentityProvider implements IdentityProvider {
  _FakeIdentityProvider(this.identity);

  final VerifiedIdentity identity;
  final List<String> tokens = [];
  final List<String> ownerClaims = [];

  @override
  Future<VerifiedIdentity> verify(String bearerToken) async {
    tokens.add(bearerToken);
    return identity;
  }

  @override
  Future<void> grantSystemOwnerClaim(String subject) async {
    ownerClaims.add(subject);
  }
}

final class _FakeSystemOwnerRepository implements SystemOwnerRepository {
  _FakeSystemOwnerRepository({Set<String>? existing})
    : existing = existing ?? <String>{};

  final Set<String> existing;
  final List<({String subject, String email})> grants = [];

  @override
  Future<bool> contains(String subject) async => existing.contains(subject);

  @override
  Future<void> grant({required String subject, required String email}) async {
    grants.add((subject: subject, email: email));
    existing.add(subject);
  }
}

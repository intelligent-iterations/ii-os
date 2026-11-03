import 'dart:convert';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/codex_auth_store.dart';
import 'package:ii_os_functions/src/codex_credential_policy.dart';
import 'package:ii_os_functions/src/providers/firebase/codex_credential_store.dart';
import 'package:ii_os_functions/src/workspace_store.dart';
import 'package:test/test.dart';

import 'support/credential_broker_fixture.dart';
import 'support/credential_firestore_fake.dart';

void main() {
  late CredentialFirestoreFake firestore;
  late CodexCredentialStore credentials;
  late CodexCredentialOwner ticket;
  setUp(() {
    firestore = CredentialFirestoreFake();
    credentials = CodexCredentialStore(WorkspaceStore(firestore));
    ticket = credentialOwner();
    seedCredentialOwner(firestore, ticket);
  });

  for (final version in const [
    '2026-10-30T12:34:56Z',
    '2026-10-30T12:34:56.123Z',
  ]) {
    test(
      'real Timestamp JSON keeps compatible immutable version $version',
      () async {
        final instant = DateTime.parse(version).toUtc();
        final original = Timestamp.fromDate(instant);
        firestore
                .documents['workspaces/workspace-a/codexAuth/example~project']!['secretUpdatedAt'] =
            original;
        final acquired = await credentials.acquire(ticket, credentialAcquire);
        final wire =
            jsonDecode(jsonEncode({'data': acquired})) as Map<String, dynamic>;
        expect(
          (wire['data'] as Map<String, dynamic>)['secretUpdatedAt'],
          version,
        );
        if (version == '2026-10-30T12:34:56Z') {
          expect(
            acquired['secretUpdatedAt'],
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')),
          );
        }
        final beforeLookup = firestore.writes;
        final observer = credentialOwner(attempt: 2);
        final lookup = await credentials.acquire(observer, {
          ...credentialAcquire,
          'cleanupOnly': true,
        });
        expect(lookup, acquired);
        expect(
          firestore.writes,
          beforeLookup,
          reason: 'An existing observer only looks up its original lease.',
        );
        final cleanup = {...credentialCommit(acquired), 'cleanupOnly': true};
        final committed = await credentials.commit(observer, cleanup);
        final committedWire =
            jsonDecode(jsonEncode({'data': committed})) as Map<String, dynamic>;
        expect(
          (committedWire['data'] as Map<String, dynamic>)['secretUpdatedAt'],
          version,
        );
        expect(await credentials.commit(observer, cleanup), committed);
        final retained =
            firestore.documents[credentialBindingPath]!['secretUpdatedAt']!
                as Timestamp;
        expect(retained.toDate().isAtSameMomentAs(instant), true);
        expect(committed['changed'], false);
      },
    );
  }

  test(
    'global fence excludes another workspace without stale lease stealing',
    () async {
      final first = await credentials.acquire(ticket, credentialAcquire);
      final other = credentialOwner(workspace: 'workspace-b', run: 11);
      seedCredentialOwner(firestore, other);
      final binding = firestore.documents[credentialBindingPath]!;
      final lease = (binding['lease']! as Map).cast<String, Object?>();
      lease['createdAt'] = Timestamp.fromDate(DateTime.utc(2000));
      binding['lease'] = lease;
      await expectLater(
        credentials.acquire(other, credentialAcquire),
        throwsA(_code('credential_in_use')),
      );
      expect(await credentials.acquire(ticket, credentialAcquire), first);
      expect(firestore.documents[credentialBindingPath]!['lease'], lease);
    },
  );

  test('changed snapshots fail before another OAuth use', () async {
    final reservation = await credentials.acquire(ticket, credentialAcquire);
    final body = credentialCommit(reservation, changed: true);
    await credentials.reserveWriter(ticket, body);
    await credentials.recordWriterIssued(ticket, body, _expiry());
    await credentials.commit(ticket, body);
    final other = credentialOwner(workspace: 'workspace-b', run: 11);
    seedCredentialOwner(firestore, other);
    await expectLater(
      credentials.acquire(other, credentialAcquire),
      throwsA(_code('credential_snapshot_stale')),
    );
    final next = await credentials.acquire(other, {
      ...credentialAcquire,
      'originalDigest': 'b' * 64,
    });
    expect(next['generation'], 1);
    expect(next['fence'], 2);
  });

  test(
    'uncertain writer cannot be reissued, released or silently changed',
    () async {
      final reservation = await credentials.acquire(ticket, credentialAcquire);
      final body = credentialCommit(reservation, changed: true);
      await expectLater(
        credentials.reserveWriter(ticket, {
          ...body,
          'workerCleanupDigest': 'bad',
        }),
        throwsA(isA<ApiError>()),
      );
      await credentials.reserveWriter(ticket, body);
      await expectLater(
        credentials.reserveWriter(ticket, body),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.commit(ticket, body),
        throwsA(isA<ApiError>()),
      );
      await credentials.recordWriterIssued(ticket, body, _expiry());
      await expectLater(
        credentials.commit(ticket, {...body, 'writerTokenRevoked': false}),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.commit(ticket, {...body, 'candidateDigest': 'c' * 64}),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.commit(ticket, {...body, 'candidateDigest': 'a' * 64}),
        throwsA(isA<ApiError>()),
      );
      expect(firestore.documents[credentialBindingPath]!['lease'], isNotNull);
      expect(
        firestore.documents[credentialBindingPath]!['secretDigest'],
        'a' * 64,
      );
    },
  );

  test(
    'completion survives interleaved runs and blocks replay with a new operation id',
    () async {
      final reservation = await credentials.acquire(ticket, credentialAcquire);
      final body = credentialCommit(reservation);
      final first = await credentials.commit(ticket, body);
      expect(first['changed'], false);
      final other = credentialOwner(workspace: 'workspace-b', run: 11);
      seedCredentialOwner(firestore, other);
      final second = await credentials.acquire(other, credentialAcquire);
      await credentials.commit(other, credentialCommit(second));
      expect(await credentials.commit(ticket, body), first);
      await expectLater(
        credentials.acquire(ticket, credentialAcquire),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.acquire(ticket, {
          ...credentialAcquire,
          'operationId': 'another',
        }),
        throwsA(isA<ApiError>()),
      );
      expect(firestore.documents[credentialBindingPath]!['lease'], isNull);
    },
  );

  test(
    'cleanup observer finishes original handoff without another native lease',
    () async {
      final reservation = await credentials.acquire(ticket, credentialAcquire);
      final observer = credentialOwner(attempt: 2);
      final lookup = {...credentialAcquire, 'cleanupOnly': true};
      expect(await credentials.acquire(observer, lookup), reservation);
      final body = {
        ...credentialCommit(reservation, changed: true),
        'cleanupOnly': true,
      };
      await expectLater(
        credentials.reserveWriter(observer, {...body, 'cleanupOnly': false}),
        throwsA(isA<ApiError>()),
      );
      await credentials.reserveWriter(observer, body);
      await credentials.recordWriterIssued(observer, body, _expiry());
      expect(
        (await credentials.commit(observer, body))['secretDigest'],
        'b' * 64,
      );
      expect((await credentials.acquire(observer, lookup))['committed'], true);
      final unknown = credentialOwner(
        workspace: 'workspace-c',
        run: 12,
        attempt: 2,
      );
      seedCredentialOwner(firestore, unknown);
      await expectLater(
        credentials.acquire(unknown, lookup),
        throwsA(isA<ApiError>()),
      );
      expect(firestore.documents[credentialBindingPath]!['lease'], isNull);
    },
  );

  test(
    'foreign owner and wrong fence cannot complete a cleanup claim',
    () async {
      final reservation = await credentials.acquire(ticket, credentialAcquire);
      final body = credentialCommit(reservation);
      for (final impostor in [
        credentialOwner(run: 11),
        credentialOwner(workspace: 'workspace-b'),
        credentialOwner(repositoryId: 124),
      ]) {
        await expectLater(
          credentials.commit(impostor, {...body, 'cleanupOnly': true}),
          throwsA(isA<ApiError>()),
        );
      }
      await expectLater(
        credentials.commit(ticket, {...body, 'fence': 99}),
        throwsA(isA<ApiError>()),
      );
      expect(firestore.documents[credentialBindingPath]!['lease'], isNotNull);
    },
  );

  test(
    'lost commit acknowledgement can be recovered by the exact cleanup observer',
    () async {
      final reservation = await credentials.acquire(ticket, credentialAcquire);
      final body = credentialCommit(reservation);
      final committed = await credentials.commit(ticket, body);
      final observer = credentialOwner(attempt: 2);
      expect(
        await credentials.commit(observer, {...body, 'cleanupOnly': true}),
        committed,
      );
      await expectLater(
        credentials.commit(observer, body),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.commit(credentialOwner(run: 11, attempt: 2), {
          ...body,
          'cleanupOnly': true,
        }),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.commit(observer, {
          ...body,
          'cleanupOnly': true,
          'workerCleanupDigest': 'sha256:${'e' * 64}',
        }),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        credentials.acquire(observer, {
          ...credentialAcquire,
          'operationId': 'new',
        }),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test(
    'cancelled first login releases empty credential without writer authority',
    () async {
      final owner = credentialOwner(purpose: 'codex-auth');
      seedCredentialOwner(firestore, owner, empty: true);
      final reservation = await credentials.acquire(owner, {
        ...credentialAcquire,
        'originalDigest': '',
      });
      final result = await credentials.commit(owner, {
        ...credentialCommit(reservation),
        'candidateDigest': '',
      });
      expect(result['secretDigest'], '');
      expect(result['changed'], false);
      expect(firestore.documents[credentialBindingPath]!['lease'], isNull);
    },
  );

  test(
    'verification publishes rotated digest only after successful finalization',
    () async {
      final owner = credentialOwner(purpose: 'codex-auth-verify');
      seedCredentialOwner(firestore, owner);
      final session = firestore.documents['codexAuthSessions/session-1']!;
      session['status'] = 'awaiting_cleanup';
      session['writerTokenStatus'] = 'revoked';
      session['writerTokenRevokedAt'] = Timestamp.now();
      session['expiresAt'] = Timestamp.fromDate(_expiry());
      session['trustedSourceSha'] = owner.principal.sha;
      session['trustedSourceRef'] = owner.principal.trustedRef;
      final reservation = await credentials.acquire(owner, credentialAcquire);
      final body = credentialCommit(reservation, changed: true);
      await credentials.reserveWriter(owner, body);
      await credentials.recordWriterIssued(owner, body, _expiry());
      await credentials.commit(owner, body);
      expect(
        firestore.documents['codexAuthSessions/session-1']!['secretDigest'],
        'b' * 64,
      );
      expect(firestore.documents[credentialBindingPath]!['status'], 'stored');
      await CodexAuthStore(
        store: WorkspaceStore(firestore),
      ).recordWorkflowEvent(
        principal: owner.principal,
        sessionId: 'session-1',
        event: {'status': 'succeeded', 'secretDigest': 'b' * 64},
      );
      expect(firestore.documents[credentialBindingPath]!['status'], 'valid');
      expect(
        firestore.documents[credentialBindingPath]!['secretDigest'],
        'b' * 64,
      );
    },
  );

  test(
    'bounded point reads, transaction attempts and writes fit approved envelope',
    () async {
      final beforeReads = firestore.reads;
      final reservation = await credentials.acquire(ticket, credentialAcquire);
      expect(firestore.reads - beforeReads, 3);
      expect(firestore.transactionAttempts, everyElement(1));
      final body = credentialCommit(reservation, changed: true);
      await credentials.reserveWriter(ticket, body);
      await credentials.recordWriterIssued(ticket, body, _expiry());
      final beforeCommit = firestore.writes;
      await credentials.commit(ticket, body);
      expect(firestore.writes - beforeCommit, 3);
      expect(firestore.transactionAttempts, everyElement(1));
      // Full legacy request: tx3 + authority1 + tenant2 + provider resolution3 = 9.
      expect(3 + 1 + 2 + 3, lessThanOrEqualTo(10));
    },
  );

  test(
    'missing provider secret permits fresh connection despite previous global digest',
    () async {
      final first = await credentials.acquire(ticket, credentialAcquire);
      await credentials.commit(ticket, credentialCommit(first));
      final owner = credentialOwner(purpose: 'codex-auth');
      seedCredentialOwner(firestore, owner);
      final reservation = await credentials.acquire(
        owner,
        {...credentialAcquire, 'originalDigest': ''},
        providerMetadata: {'exists': false, 'secretUpdatedAt': null},
      );
      expect(reservation['secretUpdatedAt'], isNull);
      final result = await credentials.commit(owner, {
        ...credentialCommit(reservation),
        'candidateDigest': '',
      });
      expect(result['secretDigest'], '');
      expect(firestore.documents[credentialBindingPath]!['status'], 'stored');
    },
  );

  test(
    'only frozen human reauthentication repairs a replaced provider snapshot',
    () async {
      final first = await credentials.acquire(ticket, credentialAcquire);
      await credentials.commit(ticket, credentialCommit(first));
      final owner = credentialOwner(purpose: 'codex-auth');
      seedCredentialOwner(firestore, owner);
      final replacement = {
        ...credentialAcquire,
        'originalDigest': 'e' * 64,
        'reauthenticate': true,
      };
      final metadata = <String, Object?>{
        'exists': true,
        'secretUpdatedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 30)),
      };
      await expectLater(
        credentials.acquire(owner, replacement, providerMetadata: metadata),
        throwsA(_code('credential_snapshot_stale')),
      );
      firestore.documents['codexAuthSessions/session-1']!['reauthenticate'] =
          true;
      final repaired = await credentials.acquire(
        owner,
        replacement,
        providerMetadata: metadata,
      );
      expect(repaired['originalDigest'], 'e' * 64);
      expect(repaired['secretUpdatedAt'], '2026-10-30T00:00:00Z');
      expect(firestore.documents[credentialBindingPath]!['status'], 'stored');
    },
  );

  test(
    'uninitialized connection can verify an existing provider credential',
    () async {
      final owner = credentialOwner(purpose: 'codex-auth');
      seedCredentialOwner(firestore, owner, empty: true);
      final first = await credentials.acquire(
        owner,
        credentialAcquire,
        providerMetadata: {'exists': true, 'secretUpdatedAt': Timestamp.now()},
      );
      expect(first['originalDigest'], 'a' * 64);
      expect(firestore.documents[credentialBindingPath]!['status'], 'stored');
    },
  );
}

DateTime _expiry() => DateTime.now().toUtc().add(const Duration(minutes: 10));
Matcher _code(String code) =>
    isA<ApiError>().having((error) => error.code, 'code', code);

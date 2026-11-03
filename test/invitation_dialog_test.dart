import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/invitation_dialogs.dart';

void main() {
  testWidgets('an empty invitation list identifies and can switch accounts', (
    tester,
  ) async {
    var switched = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showInvitationAcceptanceDialog(
                  context: context,
                  signedInEmail: 'admin@example.com',
                  loadInvitations: () async => const [],
                  onSwitchAccount: () async {
                    switched = true;
                  },
                  onAccept: (_) async {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Your invitations'), findsOneWidget);
    expect(
      find.text('No pending invitations for admin@example.com.'),
      findsOneWidget,
    );
    expect(find.text('Use another account'), findsOneWidget);

    await tester.tap(find.text('Use another account'));
    await tester.pumpAndSettle();

    expect(switched, isTrue);
    expect(find.text('Your invitations'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a matching email invitation is accepted from the list', (
    tester,
  ) async {
    String? acceptedId;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showInvitationAcceptanceDialog(
                  context: context,
                  signedInEmail: 'editor@example.com',
                  loadInvitations: () async => const [
                    {
                      'id': '33333333-3333-4333-8333-333333333333',
                      'workspaceName': 'Media operations',
                      'roleLabel': 'Editor',
                    },
                  ],
                  onAccept: (id) async {
                    acceptedId = id;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in as editor@example.com'), findsOneWidget);
    expect(find.text('Media operations'), findsOneWidget);
    expect(find.text('Role: Editor'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(
      find.byKey(
        const Key('accept-invitation-33333333-3333-4333-8333-333333333333'),
      ),
    );
    await tester.pumpAndSettle();

    expect(acceptedId, '33333333-3333-4333-8333-333333333333');
    expect(find.text('Media operations'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an acceptance failure remains actionable in the dialog', (
    tester,
  ) async {
    var attempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showInvitationAcceptanceDialog(
                  context: context,
                  signedInEmail: 'editor@example.com',
                  loadInvitations: () async => const [
                    {
                      'id': '11111111-1111-4111-8111-111111111111',
                      'workspaceName': 'Media operations',
                      'roleLabel': 'Editor',
                    },
                  ],
                  onAccept: (_) async {
                    attempts++;
                    if (attempts == 1) {
                      throw const ApiFailure(
                        'invite_email_mismatch',
                        'Sign in with the account that was invited.',
                        statusCode: 403,
                      );
                    }
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final accept = find.byKey(
      const Key('accept-invitation-11111111-1111-4111-8111-111111111111'),
    );
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(
      find.text('Sign in with the account that was invited.'),
      findsOneWidget,
    );
    expect(find.text('Media operations'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Your invitations'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('created invitation explains the email-based acceptance flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: const Scaffold(
          body: InvitationCreatedDialog(email: 'editor@example.com'),
        ),
      ),
    );

    expect(find.text('Invitation ready'), findsOneWidget);
    expect(find.text('editor@example.com'), findsOneWidget);
    expect(find.textContaining('No link or code is needed.'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_permission.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/agent_permission_dialog.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

/// A desktop-sized window, so the summary and its disclosure are both laid out.
void _desktopWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<JsonMap?> _open(WidgetTester tester, {JsonMap? profile}) async {
  JsonMap? result;
  _desktopWindow(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: IiOsTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showDialog<JsonMap>(
                  context: context,
                  builder: (_) => AgentPermissionDialog(
                    initial: profile ?? defaultAgentPermissionJson(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('opens on what the agent may do, not on the document', (
    tester,
  ) async {
    // The dialog's whole job is to get an informed yes or no about how much
    // authority an agent gets over the reader's code. It used to open on
    // schema_version, a sha256 image digest and ram_mb -- facts that cannot
    // answer that question.
    await _open(tester);

    expect(find.text('Repository maintainer'), findsOneWidget);
    expect(find.text('In your repository, this agent can'), findsOneWidget);
    expect(find.text('It cannot'), findsOneWidget);
    expect(
      find.text('Read and edit files in the selected repository'),
      findsOneWidget,
    );
    expect(
      find.text('Create new GitHub issues or Project items'),
      findsOneWidget,
    );

    // The enforcement mechanism is present but not in the way.
    expect(find.textContaining('sha256:'), findsNothing);
    expect(find.text('Runtime details'), findsOneWidget);
  });

  testWidgets('runtime facts stay one disclosure away', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Runtime details'));
    await tester.pumpAndSettle();

    expect(find.text('Agent runtime'), findsOneWidget);
    expect(
      find.textContaining('.ii-os/runtimes/repository-maintainer.json'),
      findsOneWidget,
    );
    expect(
      find.textContaining('.ii-os/runtimes/execution-binding.json'),
      findsOneWidget,
    );
    expect(find.textContaining('sha256:'), findsNWidgets(2));
  });

  testWidgets('the raw document is still reachable for an author', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Edit as JSON'));
    await tester.pumpAndSettle();

    expect(find.text('Agent permission JSON'), findsOneWidget);
    expect(find.text('Agent permission template'), findsOneWidget);
    expect(find.textContaining('"schema_version"'), findsOneWidget);
  });

  testWidgets('an edit made as JSON reaches the summary and the install', (
    tester,
  ) async {
    // The failure this guards: rendering the summary from the pre-edit profile
    // would show one boundary while installing another.
    JsonMap? installed;
    _desktopWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  installed = await showDialog<JsonMap>(
                    context: context,
                    builder: (_) => AgentPermissionDialog(
                      initial: defaultAgentPermissionJson(),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit as JSON'));
    await tester.pumpAndSettle();

    final edited = defaultAgentPermissionJson()
      ..['display_name'] = 'Read-only reviewer'
      ..['allowed_actions'] = ['Read files in the selected repository'];
    await tester.enterText(
      find.byType(TextField),
      const JsonEncoder.withIndent('  ').convert(edited),
    );

    await tester.tap(find.text('Back to summary'));
    await tester.pumpAndSettle();

    expect(find.text('Read-only reviewer'), findsOneWidget);
    expect(find.text('Read files in the selected repository'), findsOneWidget);

    await tester.tap(find.text('Install these permissions'));
    await tester.pumpAndSettle();

    expect(installed?['display_name'], 'Read-only reviewer');
  });

  testWidgets('invalid JSON blocks the switch back and says why', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Edit as JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{not json');
    await tester.tap(find.text('Back to summary'));
    await tester.pumpAndSettle();

    // Still in the editor, with the parse failure shown on the field.
    expect(find.text('Agent permission template'), findsOneWidget);
    expect(find.text('In your repository, this agent can'), findsNothing);
  });

  testWidgets('installing from the summary returns the profile unchanged', (
    tester,
  ) async {
    JsonMap? installed;
    _desktopWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  installed = await showDialog<JsonMap>(
                    context: context,
                    builder: (_) => AgentPermissionDialog(
                      initial: defaultAgentPermissionJson(),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install these permissions'));
    await tester.pumpAndSettle();

    expect(installed?['id'], 'repository-maintainer');
    expect(installed, defaultAgentPermissionJson());
  });
}

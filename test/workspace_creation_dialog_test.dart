import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/organization_access.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/workspace_creation_dialog.dart';

void main() {
  testWidgets('returns a named workspace inside the selected organization', (
    tester,
  ) async {
    WorkspaceCreationRequest? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showWorkspaceCreationDialog(
                  context: context,
                  organization: const OrganizationAccess(
                    id: 'org-1',
                    name: 'Intelligent Iterations',
                    role: 'Owner',
                    capabilities: {},
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('New workspace'), findsOneWidget);
    expect(find.textContaining('Intelligent Iterations'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Friends');
    await tester.pump();
    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Friends');
    expect(result?.environment, 'dev');
  });
}

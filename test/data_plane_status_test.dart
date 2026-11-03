import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/data_plane_status.dart';

import 'page_golden_harness.dart';

void main() {
  testWidgets('renders a not-connected state instead of crashing', (
    tester,
  ) async {
    // The regression: `controller.connection!` turned Project Admin -- the page
    // you visit in order to set the connection up -- into a red screen for
    // every workspace that had not set one up yet, which is every new one.
    final controller = pageController();
    addTearDown(controller.dispose);
    expect(controller.connection, isNull, reason: 'the state under test');

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(body: DataPlaneStatusPanel(controller: controller)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('not connected'), findsOneWidget);
    expect(find.textContaining('no inherited GCP project yet'), findsOneWidget);
  });

  testWidgets('renders the connection when there is one', (tester) async {
    // Negative control: proves the test above is not passing because the panel
    // renders the empty state unconditionally.
    final controller = pageController();
    addTearDown(controller.dispose);
    controller.connection = const DataPlaneConnectionModel(
      workspaceId: 'workspace-1',
      projectId: 'acme-media',
      projectNumber: '1234567890',
      databaseId: '(default)',
      region: 'us-central1',
      bucket: 'acme-media-artifacts',
      dataServiceAccount: 'data@acme-media.iam.gserviceaccount.com',
      uploadServiceAccount: 'upload@acme-media.iam.gserviceaccount.com',
      workloadIdentityProvider: 'projects/123/locations/global/wip/github',
      authProjectId: 'acme-media',
      webOrigin: 'https://acme.example.com',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(body: DataPlaneStatusPanel(controller: controller)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('not connected'), findsNothing);
    expect(find.textContaining('acme-media-artifacts'), findsWidgets);
  });

  testWidgets('check rows say what a check means, not what it probed', (
    tester,
  ) async {
    // Rule 12. "GCS object canary" is the validator's name for its own probe:
    // it says what the code did and never what it means for the reader's setup.
    // A column of those reads as a log, on the page an operator opens precisely
    // because they do not yet know whether their cloud project is wired up.
    const validation = DataPlaneValidationModel(
      status: 'action_required',
      validatedAt: null,
      checks: [
        DataPlaneCheckModel(
          id: 'object_crud',
          label: 'GCS object canary',
          status: 'passed',
          detail: 'Wrote and deleted gs://acme-media-artifacts/.iios-canary',
        ),
        DataPlaneCheckModel(
          id: 'bucket_admin_denied',
          label: 'Bucket administration denied',
          status: 'action_required',
          detail: 'storage.buckets.update was not denied for the broker.',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DataPlaneCheckList(validation: validation),
          ),
        ),
      ),
    );

    expect(find.text('Media can be written and read back'), findsOneWidget);
    expect(find.text('ii-os cannot administer your bucket'), findsOneWidget);

    // The operator text still exists -- collapsed, and labelled as such.
    expect(find.text('Technical details'), findsOneWidget);
    expect(find.text('GCS object canary'), findsNothing);

    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('GCS object canary'), findsOneWidget);
  });

  testWidgets(
    'an unknown check id does not borrow the validator\u2019s words',
    (tester) async {
      // Rule 12's fallback: a check with no sentence written for a person stays
      // out of the primary surface's vocabulary rather than printing the
      // backend's.
      const validation = DataPlaneValidationModel(
        status: 'action_required',
        validatedAt: null,
        checks: [
          DataPlaneCheckModel(
            id: 'some_future_check',
            label: 'Egress interconnect parity',
            status: 'action_required',
            detail: 'peering_state != ACTIVE',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DataPlaneCheckList(validation: validation),
            ),
          ),
        ),
      );

      expect(find.text('Egress interconnect parity'), findsNothing);
      expect(
        find.textContaining('could not describe this check'),
        findsOneWidget,
      );
    },
  );
}

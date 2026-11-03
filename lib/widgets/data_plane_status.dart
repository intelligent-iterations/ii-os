import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/data_plane_connection.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';

class DataPlaneCheckList extends StatelessWidget {
  const DataPlaneCheckList({required this.validation, super.key});

  final DataPlaneValidationModel validation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final check in validation.checks) ...[
          _ConnectionCheckRow(check: check),
          if (check != validation.checks.last) const Divider(),
        ],
        if (validation.checks.isNotEmpty) ...[
          IiOsGap.vSm,
          DataPlaneTechnicalChecks(checks: validation.checks),
        ],
      ],
    );
  }
}

/// What the panel shows before a data plane exists.
///
/// Says so plainly rather than hiding the panel: the operator is on this page
/// to configure the connection, and an absent panel reads as a broken page.
class _DataPlaneNotConnected extends StatelessWidget {
  const _DataPlaneNotConnected({required this.organizationBound});

  final bool organizationBound;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'GCP data plane',
              trailing: const StatusPill(
                'not connected',
                color: IiOsColors.muted,
              ),
            ),
            IiOsGap.vSm,
            Text(
              organizationBound
                  ? 'This organization has no GCP project yet. An Organization '
                        'Admin can add one with a one-time service-account '
                        'check, then child workspaces select it.'
                  : 'This legacy workspace has no inherited GCP project yet. '
                        'Ask an Organization Admin to add or promote one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class DataPlaneStatusPanel extends StatelessWidget {
  const DataPlaneStatusPanel({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // An organization has no connection until someone configures one. The
    // previous `!` here
    // turned Project Admin -- the page you go to in order to *set up* the data
    // plane -- into a red screen for every operator who had not set it up yet.
    final connection = controller.connection;
    if (connection == null) {
      return _DataPlaneNotConnected(
        organizationBound:
            controller.workspace?.organizationId.isNotEmpty == true,
      );
    }
    final validation = controller.connectionValidation;
    final ready = validation?.ready ?? true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'GCP data plane',
              trailing: StatusPill(
                ready ? 'connected' : 'check required',
                color: ready ? IiOsColors.green : IiOsColors.amber,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _ConnectionFact(label: 'Project', value: connection.projectId),
                _ConnectionFact(
                  label: 'Control database',
                  value: connection.databaseId,
                ),
                _ConnectionFact(label: 'Bucket', value: connection.bucket),
                _ConnectionFact(label: 'Region', value: connection.region),
                _ConnectionFact(
                  label: 'Web origin',
                  value: connection.webOrigin,
                ),
              ],
            ),
            if (validation != null) ...[
              IiOsGap.vMd,
              const Divider(),
              DataPlaneCheckList(validation: validation),
            ],
            IiOsGap.vMd,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.connectionBusy
                      ? null
                      : () => _revalidate(context),
                  icon: controller.connectionBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.scanSearch, size: 17),
                  label: const Text('Run checks'),
                ),
                StatusPill(
                  connection.isOrganizationBound
                      ? 'organization scoped'
                      : 'workspace scoped',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _revalidate(BuildContext context) async {
    try {
      final result = await controller.revalidateDataPlane();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.ready
                  ? 'GCP data plane checks passed.'
                  : 'GCP data plane needs attention.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }
}

/// What each data-plane check confirms, in the words of the person who owns the
/// cloud project it runs against.
///
/// Rule 12 (`docs/ii-os-frontend.md` § Rules): "GCS object canary" and "Bucket
/// administration denied" are the validator's names for its own probes. They
/// tell the reader what the code did, never what it means for their setup, and
/// a column of them reads as a log. The raw pair still renders, in the
/// technical disclosure below the row.
const _dataPlaneCheckCopy = {
  'bootstrap_identity': (
    'Google accepted the service account',
    'The credential was used for this check only and was not stored.',
  ),
  'bootstrap_project': (
    'Your GCP project is visible',
    'ii-os found the project identity needed for this resource.',
  ),
  'bootstrap_discovery': (
    'Project discovery needs access',
    'Grant the service account read access to the project resources and try again.',
  ),
  'bootstrap_resource_limit': (
    'Choose the exact GCP resources',
    'Name the bucket, upload identity, and identity provider to narrow the result.',
  ),
  'bootstrap_bucket': (
    'Choose an organization media bucket',
    'Label one accessible bucket for this organization or enter its exact name.',
  ),
  'bootstrap_upload_identity': (
    'Choose a workflow upload identity',
    'Enter the service account that approved GitHub workflows will impersonate.',
  ),
  'bootstrap_wif': (
    'Choose the GitHub identity provider',
    'Enter the active provider used for repository-scoped workflow uploads.',
  ),
  'github_secret_discovery': (
    'Add an organization GitHub App secret',
    'Label a Secret Manager secret for this organization and use the supported App secret shape.',
  ),
  'github_app_discovery': (
    'Your GitHub Apps are discoverable',
    'ii-os verified their secrets, installations, repositories, and permissions.',
  ),
  'github_secret_limit': (
    'Too many GitHub App secrets were found',
    'Keep this organization project to no more than 20 labelled App secrets.',
  ),
  'github_installation_discovery': (
    'GitHub App installation needs attention',
    'Install the App and keep the organization total within 20 installations.',
  ),
  'cloud_identity': (
    'ii-os can reach your cloud project',
    'The broker identity you granted is accepted by your project.',
  ),
  'firestore_crud': (
    'Your workspace records are readable',
    'ii-os can store workspace settings and audit metadata.',
  ),
  'bucket_workspace_binding': (
    'Your media bucket belongs to this tenant',
    'The bucket is labelled for this tenant, so another tenant cannot claim it.',
  ),
  'bucket_policy': (
    'Your bucket is private',
    'Only identities you granted can reach the media in it.',
  ),
  'bucket_retention': (
    'Your media is kept as long as you asked',
    'The bucket\u2019s retention matches the policy you configured.',
  ),
  'bucket_cors': (
    'Your browser can load media directly',
    'Media reaches the page from your bucket without passing through ii-os.',
  ),
  'object_crud': (
    'Media can be written and read back',
    'A disposable test object was written to your bucket and removed again.',
  ),
  'bucket_admin_denied': (
    'ii-os cannot administer your bucket',
    'The broker can move objects you authorize and nothing else.',
  ),
  'read_signing': (
    'Viewing links expire',
    'Media is shown through short-lived links signed for the viewer.',
  ),
  'github_app_secret': (
    'Your GitHub App key stays yours',
    'ii-os stores only the secret\u2019s location in your project, never its value.',
  ),
  'firebase_asset_boundary': (
    'No media is stored by ii-os',
    'The control plane holds references to your media, never the files.',
  ),
};

class _ConnectionCheckRow extends StatelessWidget {
  const _ConnectionCheckRow({required this.check});

  final DataPlaneCheckModel check;

  @override
  Widget build(BuildContext context) {
    final passed = check.passed;
    final color = passed ? IiOsColors.green : IiOsColors.red;
    final copy = _dataPlaneCheckCopy[check.id];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      leading: Icon(
        passed ? LucideIcons.circleCheck : LucideIcons.circleAlert,
        size: 19,
        color: color,
      ),
      title: Text(copy?.$1 ?? 'Connection check'),
      subtitle: Text(
        copy?.$2 ??
            'ii-os could not describe this check. Open Technical details to '
                'see exactly what it verified.',
      ),
      trailing: Text(
        passed ? 'Passed' : 'Action required',
        style: TextStyle(color: color, fontSize: 12, letterSpacing: 0),
      ),
    );
  }
}

/// The raw validator output, for whoever is debugging the connection.
///
/// Collapsed and titled so the reader knows they are opting into operator text
/// -- the same contract `_TechnicalChecks` honours on the setup wizard.
class DataPlaneTechnicalChecks extends StatelessWidget {
  const DataPlaneTechnicalChecks({required this.checks, super.key});

  final List<DataPlaneCheckModel> checks;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    leading: const Icon(LucideIcons.listChecks, size: 18),
    title: const Text('Technical details'),
    subtitle: Text(
      '${checks.where((check) => check.passed).length} of ${checks.length} checks passed',
    ),
    children: [
      for (final check in checks)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: IiOsSpacing.xxs),
          leading: Icon(
            check.passed ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 18,
            color: check.passed ? IiOsColors.green : IiOsColors.red,
          ),
          title: Text(check.label),
          subtitle: check.detail.isEmpty ? null : Text(check.detail),
        ),
    ],
  );
}

class _ConnectionFact extends StatelessWidget {
  const _ConnectionFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          SelectableText(value, maxLines: 2),
        ],
      ),
    );
  }
}

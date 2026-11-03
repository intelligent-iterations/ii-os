import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import 'organization_resources_screen.dart';

/// Compatibility destination for old connection URLs.
///
/// There is no workspace credential flow anymore. A loaded workspace opens
/// its organization resource page; an unavailable session gets a recoverable
/// state without accepting any credential material.
class DataPlaneConnectionScreen extends StatelessWidget {
  const DataPlaneConnectionScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final workspace = controller.workspace;
    final organization = session?.organizationFor(workspace?.id);
    if (session != null && workspace != null && organization != null) {
      return OrganizationResourcesScreen(controller: controller);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('ii-os')),
      body: PageFrame(
        title: 'Organization setup unavailable',
        subtitle: 'ii-os could not load your organization membership.',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reload your session. Cloud and GitHub resources are '
                  'managed once by an Organization Admin and inherited by '
                  'child workspaces.',
                ),
                IiOsGap.vMd,
                FilledButton(
                  onPressed: controller.loading
                      ? null
                      : () => controller.initialize(),
                  child: const Text('Reload session'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

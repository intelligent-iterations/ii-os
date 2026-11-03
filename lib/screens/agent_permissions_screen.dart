import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/agent_permission.dart';
import '../models/models.dart';
import '../repositories/agent_permissions_repository.dart';
import '../state/app_controller.dart';
import '../view_models/agent_permissions_view_model.dart';
import '../widgets/codex_auth_session_card.dart';
import '../widgets/common.dart';
import 'agent_permission_dialog.dart';

part 'agent_permissions_widgets.dart';

class AgentPermissionsScreen extends StatelessWidget {
  const AgentPermissionsScreen({
    required this.controller,
    this.repository,
    this.ref,
    this.onSelectionChanged,
    super.key,
  });

  final AppController controller;
  final String? repository;
  final String? ref;
  final void Function(String?, String)? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.workspace!;
    return ViewModelBuilder<AgentPermissionsViewModel>.reactive(
      key: ValueKey('${workspace.id}:${repository ?? ''}'),
      viewModelBuilder: () => AgentPermissionsViewModel(
        workspaceId: workspace.id,
        repositories: workspace.repositories,
        repositoryApi: AgentPermissionsRepository(controller.api),
        initialRepository: repository,
        onSelectionChanged: onSelectionChanged,
      ),
      onViewModelReady: (model) {
        model.start();
        _canonicalize(model);
      },
      builder: (context, model, _) => PageFrame(
        title: 'Agent permissions',
        subtitle: 'Choose what an agent may do, then verify its Codex sign-in',
        actions: [
          if (controller.can('agent.permissions.manage')) ...[
            Tooltip(
              message: model.hasRecommendedAccess
                  ? 'Run a real Codex sign-in and smoke test.'
                  : 'Install the recommended access before verifying Codex.',
              child: OutlinedButton.icon(
                onPressed:
                    model.repository == null ||
                        !model.hasRecommendedAccess ||
                        model.startingCodex ||
                        model.codexSession?.succeeded == true
                    ? null
                    : model.startCodexVerification,
                icon: model.startingCodex
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.keyRound, size: 17),
                label: Text(
                  model.codexSession?.succeeded == true
                      ? 'Codex verified'
                      : 'Verify Codex',
                ),
              ),
            ),
          ],
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (model.codexSession != null || model.codexError != null) ...[
              CodexAuthSessionCard(
                session: model.codexSession,
                error: model.codexError,
                onRetry: model.startingCodex
                    ? null
                    : model.startCodexVerification,
              ),
            ],
            IiOsGap.vMd,
            _AgentPermissionControls(model: model),
            IiOsGap.vMd,
            _AgentPermissionBody(
              model: model,
              canManage: controller.can('agent.permissions.manage'),
              onInstall: (profile) => _edit(context, model, profile),
              onEdit: (profile) => _edit(context, model, profile),
            ),
          ],
        ),
      ),
    );
  }

  void _canonicalize(AgentPermissionsViewModel model) {
    if (repository == model.repository &&
        (ref ?? AgentPermissionsViewModel.ref) ==
            AgentPermissionsViewModel.ref) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSelectionChanged?.call(model.repository, AgentPermissionsViewModel.ref);
    });
  }

  Future<void> _edit(
    BuildContext context,
    AgentPermissionsViewModel model, [
    AgentPermissionModel? profile,
  ]) async {
    final result = await showDialog<JsonMap>(
      context: context,
      builder: (context) => AgentPermissionDialog(
        initial: profile?.installableJson ?? defaultAgentPermissionJson(),
      ),
    );
    if (result == null || !context.mounted) return;
    final installed = await model.install(result);
    if (!context.mounted) return;
    if (!installed) {
      showFailure(
        context,
        model.errorMessage ?? 'Access could not be installed.',
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Installing agent access. Refresh when the GitHub run finishes.',
        ),
      ),
    );
  }
}

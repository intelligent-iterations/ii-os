import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../view_models/interactive_sessions_view_model.dart';
import '../widgets/common.dart';

class InteractiveSessionsList extends StatelessWidget {
  const InteractiveSessionsList({
    required this.model,
    required this.onSelect,
    super.key,
  });

  final InteractiveSessionsViewModel model;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Terminal sessions',
    subtitle: 'Disposable multiplayer shells on a granted Fleet pool',
    actions: [
      OutlinedButton.icon(
        onPressed: model.isBusy ? null : model.load,
        icon: const Icon(LucideIcons.refreshCw, size: IiOsIconSize.md),
        label: const Text('Refresh'),
      ),
      FilledButton.icon(
        onPressed: model.isBusy ? null : () => _create(context),
        icon: const Icon(LucideIcons.terminal, size: IiOsIconSize.md),
        label: const Text('New terminal session'),
      ),
    ],
    child: _InteractiveSessionsBody(model: model, onSelect: onSelect),
  );

  Future<void> _create(BuildContext context) async {
    final pools = model.runnerPools;
    if (pools.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Grant this workspace a Fleet pool with runtime-docker and interactive-pty first.',
          ),
        ),
      );
      return;
    }
    final selected = await showDialog<InteractiveRunnerPoolOption>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose where this session runs'),
        children: [
          for (final pool in pools)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(pool),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.server),
                title: Text(pool.name),
                subtitle: Text(
                  '${pool.providerPoolId} · up to ${pool.maxConcurrent} session${pool.maxConcurrent == 1 ? '' : 's'}',
                ),
                trailing: pool.primary ? const Text('Primary') : null,
              ),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    final session = await model.create(selected.resourceId);
    if (session != null && context.mounted) onSelect?.call(session.id);
  }
}

class _InteractiveSessionsBody extends StatelessWidget {
  const _InteractiveSessionsBody({required this.model, required this.onSelect});

  final InteractiveSessionsViewModel model;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (model.showLoadingSurface) {
      return const LoadingSurface(label: 'Loading terminal sessions');
    }
    if (model.errorMessage case final error? when model.sessions.isEmpty) {
      return ErrorSurface(
        title: 'Terminal sessions could not be loaded',
        message: error,
        onRetry: model.load,
      );
    }
    if (model.sessions.isEmpty) {
      return const Card(
        child: EmptyState(
          title: 'No terminal sessions',
          message:
              'Start a temporary shell on your personal host or another Fleet pool granted to this workspace.',
          icon: LucideIcons.terminal,
        ),
      );
    }
    return ListView.separated(
      itemCount: model.sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: IiOsSpacing.sm),
      itemBuilder: (context, index) {
        final session = model.sessions[index];
        return _SessionCard(session: session, onTap: onSelect);
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});

  final InteractiveSessionModel session;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: session.terminal ? null : () => onTap?.call(session.id),
      leading: const Icon(LucideIcons.squareTerminal),
      title: Text(
        'Session ${session.id.substring(0, session.id.length.clamp(0, 8))}',
      ),
      subtitle: Text(
        '${session.poolId} · ${session.participants.length} participant${session.participants.length == 1 ? '' : 's'}',
      ),
      trailing: Chip(label: Text(session.lifecycle)),
    ),
  );
}

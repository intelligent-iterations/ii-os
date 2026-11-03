import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/workshop_ticket.dart';
import '../repositories/workshop_repository.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../view_models/production_line_view_model.dart';
import '../widgets/common.dart';
import 'software_workshop_ticket_widgets.dart';

/// One production line: the tickets for its repository on its board, under the
/// permission scope it carries.
class ProductionLineScreen extends StatelessWidget {
  const ProductionLineScreen({
    required this.controller,
    required this.lineId,
    required this.onOpenGitHub,
    required this.onManagePermissions,
    super.key,
  });

  final AppController controller;
  final String lineId;
  final ValueChanged<String> onOpenGitHub;
  final ValueChanged<String> onManagePermissions;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ProductionLineViewModel>.reactive(
      viewModelBuilder: () => ProductionLineViewModel(
        lines: controller.productionLines.repository,
        workshop: WorkshopApiRepository(controller.api),
        workspaceId: controller.workspace!.id,
        lineId: lineId,
      ),
      onViewModelReady: (model) => model.load(),
      builder: (context, model, child) => PageFrame(
        title: model.line?.name ?? 'Production line',
        subtitle: model.line == null
            ? null
            : '${model.line!.repository} · ${model.line!.permissionProfileId}',
        leading: model.line == null
            ? null
            : IiOsIdentityGlyph(
                colorToken: model.line!.colorToken,
                iconToken: model.line!.iconToken,
                size: IiOsIdentityGlyph.headerSize,
                needsAttention: model.attention != null,
                semanticLabel: model.line!.name,
              ),
        actions: [
          IconButton.outlined(
            tooltip: 'Refresh this production line',
            onPressed: model.loadingBoard ? null : model.load,
            icon: const Icon(LucideIcons.refreshCw, size: 17),
          ),
        ],
        child: _Body(
          model: model,
          onOpenGitHub: onOpenGitHub,
          onManagePermissions: onManagePermissions,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.model,
    required this.onOpenGitHub,
    required this.onManagePermissions,
  });

  final ProductionLineViewModel model;
  final ValueChanged<String> onOpenGitHub;
  final ValueChanged<String> onManagePermissions;

  @override
  Widget build(BuildContext context) {
    if (model.showsInitialSpinner) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: IiOsSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final failure = model.failure;
    if (failure != null && model.line == null) {
      return Card(
        child: EmptyState(
          title: 'This line could not be opened',
          message: failure,
          icon: LucideIcons.triangleAlert,
          action: FilledButton(
            onPressed: model.load,
            child: const Text('Retry'),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.attention != null)
          _AttentionNotice(
            detail: model.attention!,
            onManagePermissions: () =>
                onManagePermissions(model.line!.repository),
          ),
        _FilterRow(model: model),
        IiOsGap.vMd,
        _Board(
          model: model,
          onOpenGitHub: onOpenGitHub,
          onManagePermissions: onManagePermissions,
        ),
      ],
    );
  }
}

class _AttentionNotice extends StatelessWidget {
  const _AttentionNotice({
    required this.detail,
    required this.onManagePermissions,
  });

  final String detail;
  final VoidCallback onManagePermissions;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.shieldAlert,
            color: IiOsColors.amber,
            size: 21,
          ),
          IiOsGap.hSm,
          Expanded(child: Text(detail)),
          IiOsGap.hSm,
          OutlinedButton(
            onPressed: onManagePermissions,
            child: const Text('Manage permissions'),
          ),
        ],
      ),
    ),
  );
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.model});

  final ProductionLineViewModel model;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.md),
      child: DropdownButtonFormField<WorkshopFilter>(
        key: ValueKey('production-line-filter-${model.filter.value}'),
        initialValue: model.filter,
        decoration: const InputDecoration(labelText: 'View'),
        items: WorkshopFilter.values
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(value.label)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) model.changeFilter(value);
        },
      ),
    ),
  );
}

class _Board extends StatelessWidget {
  const _Board({
    required this.model,
    required this.onOpenGitHub,
    required this.onManagePermissions,
  });

  final ProductionLineViewModel model;
  final ValueChanged<String> onOpenGitHub;
  final ValueChanged<String> onManagePermissions;

  @override
  Widget build(BuildContext context) {
    final tickets = model.visibleTickets;
    if (tickets.isEmpty) {
      return Card(
        child: EmptyState(
          title: model.tickets.isEmpty
              ? 'This line is clear'
              : 'No tickets in this view',
          message: model.tickets.isEmpty
              ? 'Create a focused ticket when you are ready to hand work to an '
                    'agent.'
              : 'Choose another view to see the rest of this line\u2019s tickets.',
          icon: LucideIcons.ticketCheck,
        ),
      );
    }
    final selected = model.selectedTicket;
    return LayoutBuilder(
      builder: (context, constraints) {
        final list = Column(
          children: [
            for (var index = 0; index < tickets.length; index++) ...[
              WorkshopTicketListCard(
                ticket: tickets[index],
                selected: tickets[index].itemId == selected?.itemId,
                onSelected: () => model.selectTicket(tickets[index].itemId),
              ),
              if (index != tickets.length - 1) IiOsGap.vSm,
            ],
          ],
        );
        final detail = selected == null
            ? const Card(
                child: EmptyState(
                  title: 'Select a ticket',
                  message:
                      'Open a ticket to review its brief, permissions, status, '
                      'and agent handoff.',
                  icon: LucideIcons.panelRightOpen,
                ),
              )
            : _ProductionLineTicketDetail(
                model: model,
                ticket: selected,
                onOpenGitHub: onOpenGitHub,
                onManagePermissions: onManagePermissions,
              );
        if (constraints.maxWidth < IiOsBreakpoints.sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              list,
              if (selected != null) ...[IiOsGap.vMd, detail],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: list),
            IiOsGap.hMd,
            Expanded(flex: 3, child: detail),
          ],
        );
      },
    );
  }
}

class _ProductionLineTicketDetail extends StatelessWidget {
  const _ProductionLineTicketDetail({
    required this.model,
    required this.ticket,
    required this.onOpenGitHub,
    required this.onManagePermissions,
  });

  final ProductionLineViewModel model;
  final WorkshopTicket ticket;
  final ValueChanged<String> onOpenGitHub;
  final ValueChanged<String> onManagePermissions;

  @override
  Widget build(BuildContext context) => WorkshopTicketDetail(
    ticket: ticket,
    readiness: model.readinessFor(ticket),
    profile: model.board?.profilesVerified == true
        ? ticket.installedProfile(model.profiles)
        : null,
    statusOptions: model.statusOptions,
    canWrite: false,
    busy: model.ticketBusy(ticket.itemId),
    onEdit: () => onOpenGitHub(ticket.url),
    onDelete: () {},
    onReview: () => onOpenGitHub(ticket.url),
    onPause: () => onOpenGitHub(ticket.url),
    onStatusChanged: (optionId) => model.setStatus(ticket, optionId),
    onOpenGitHub: () => onOpenGitHub(ticket.url),
    onManagePermissions: () => onManagePermissions(ticket.repository),
    onOpenPullRequest: () => onOpenGitHub(ticket.finalPullRequestUrl),
  );
}

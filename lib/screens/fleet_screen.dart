import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/fleet_repository.dart';
import '../state/app_controller.dart';
import '../view_models/fleet_view_model.dart';
import '../widgets/common.dart';

part 'fleet_machine_list.dart';
part 'fleet_machines.dart';
part 'fleet_panels.dart';
part 'fleet_support.dart';

/// The machines an organization's work runs on.
///
/// Organization-tier rather than per-project: the same machines serve every
/// project in the tenant, so scoping this to one would show a partial truth and
/// imply the fleet belongs to a project it does not belong to.
class FleetScreen extends StatelessWidget {
  const FleetScreen({required this.controller, this.repository, super.key});

  final AppController controller;
  final FleetRepository? repository;

  @override
  Widget build(BuildContext context) {
    final organization = controller.session?.organizationFor(
      controller.workspace?.id,
    );
    if (organization == null) return const _NoOrganization();
    return _FleetForOrganization(
      controller: controller,
      organization: organization,
      repository: repository,
    );
  }
}

class _FleetForOrganization extends StatelessWidget {
  const _FleetForOrganization({
    required this.controller,
    required this.organization,
    required this.repository,
  });

  final AppController controller;
  final OrganizationAccess organization;
  final FleetRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<FleetViewModel>.reactive(
      viewModelBuilder: () => FleetViewModel(
        organizationId: organization.id,
        fleet: repository ?? FleetApiRepository(controller.api),
        canIssueCredential: organization.can('org.credentials.manage'),
      ),
      onViewModelReady: (model) => model.start(),
      builder: (context, model, _) => PageFrame(
        title: 'Infrastructure',
        subtitle: 'The machines ${organization.name} runs its work on',
        actions: [
          OutlinedButton.icon(
            onPressed: model.isBusy ? null : model.load,
            icon: const Icon(LucideIcons.refreshCw, size: IiOsIconSize.md),
            label: const Text('Refresh'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (model.isBusy && model.hasReport)
              const RefreshingStrip(label: 'Refreshing infrastructure\u2026'),
            _FleetBody(model: model),
          ],
        ),
      ),
    );
  }
}

class _FleetBody extends StatelessWidget {
  const _FleetBody({required this.model});

  final FleetViewModel model;

  @override
  Widget build(BuildContext context) {
    final report = model.report;
    if (model.isFirstLoad) {
      return const LoadingSurface(label: 'Loading infrastructure');
    }
    if (model.errorMessage != null && report == null) {
      return ErrorSurface(
        title: 'Infrastructure could not be loaded',
        message: model.errorMessage!,
        onRetry: model.load,
      );
    }
    if (report == null) {
      return _NoFleetConnected(canConnect: model.canIssueCredential);
    }
    if (report.machines.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.server,
        title: 'No machines reported',
        message:
            'The fleet is reporting in, but it has no machines registered yet.',
      );
    }
    return _FleetContent(model: model, report: report);
  }
}

class _FleetContent extends StatelessWidget {
  const _FleetContent({required this.model, required this.report});

  final FleetViewModel model;
  final FleetReport report;

  @override
  Widget build(BuildContext context) {
    final selected = model.selectedMachine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report.stale) _StaleNotice(observedAt: report.observedAt),
        IiOsGap.vMd,
        _FleetSummary(report: report),
        IiOsGap.vXl,
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide =
                constraints.maxWidth >= IiOsBreakpoints.sideBySide;
            final machines = _MachineGrid(
              report: report,
              selectedId: model.selectedMachineId,
              onSelect: model.selectMachine,
            );
            final panels = _FleetSidePanels(report: report);
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [machines, IiOsGap.vXl, panels],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: machines),
                IiOsGap.hXl,
                Expanded(flex: 2, child: panels),
              ],
            );
          },
        ),
        if (selected != null) ...[
          IiOsGap.vXl,
          _MachineDetail(
            machine: selected,
            work: report.workOn(selected.id),
            onClose: () => model.selectMachine(null),
          ),
        ],
      ],
    );
  }
}

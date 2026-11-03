import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/agent_usage.dart';
import '../repositories/agent_usage_repository.dart';
import '../state/app_controller.dart';
import '../view_models/agent_usage_view_model.dart';
import '../widgets/common.dart';

part 'agent_usage_widgets.dart';
part 'agent_usage_billing_widgets.dart';
part 'agent_usage_mode_widgets.dart';

class AgentUsageScreen extends StatelessWidget {
  const AgentUsageScreen({
    required this.controller,
    required this.days,
    required this.origin,
    this.onFilterChanged,
    this.loader,
    super.key,
  });

  final AppController controller;
  final int days;
  final AgentExecutionOrigin origin;
  final void Function(int days, AgentExecutionOrigin origin)? onFilterChanged;
  final AgentUsageLoader? loader;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AgentUsageViewModel>.reactive(
      viewModelBuilder: () => AgentUsageViewModel(
        workspaceId: controller.workspace!.id,
        loader: loader ?? AgentUsageRepository(controller.api).read,
        days: days,
        origin: origin,
        onFilterChanged: onFilterChanged,
      ),
      onViewModelReady: (model) => model.start(),
      builder: (context, model, _) => PageFrame(
        title: 'Agent usage',
        subtitle: 'Prompts, tokens, models, and the jobs that ran',
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
            _UsageFilters(
              days: model.days,
              origin: model.origin,
              onChanged: model.changeFilters,
            ),
            IiOsGap.vMd,
            if (model.isBusy && model.report != null)
              const RefreshingStrip(label: 'Refreshing agent usage\u2026'),
            _AgentUsageBody(model: model),
          ],
        ),
      ),
    );
  }
}

class _AgentUsageBody extends StatelessWidget {
  const _AgentUsageBody({required this.model});

  final AgentUsageViewModel model;

  @override
  Widget build(BuildContext context) {
    final report = model.report;
    if (model.isBusy && report == null) {
      return const LoadingSurface(label: 'Loading agent usage');
    }
    if (model.errorMessage != null && report == null) {
      return ErrorSurface(
        title: 'Agent usage could not be loaded',
        message: model.errorMessage!,
        onRetry: model.load,
      );
    }
    if (report == null || !report.configured) {
      return const Card(
        child: EmptyState(
          title: 'Agent usage storage is not connected',
          message:
              'Configure the workspace-scoped BigQuery usage table, then send agent usage reports to it.',
          icon: LucideIcons.database,
        ),
      );
    }
    if (report.isEmpty) {
      return const Card(
        child: EmptyState(
          title: 'No agent usage in this view',
          message:
              'No prompt or token reports match the selected time window and execution origin.',
          icon: LucideIcons.chartNoAxesColumn,
        ),
      );
    }
    return _UsageReport(report: report);
  }
}

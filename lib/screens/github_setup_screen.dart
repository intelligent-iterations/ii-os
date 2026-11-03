import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/github_setup_readiness.dart';
import '../services/api_client.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/github_setup_onboarding.dart';
import 'github_setup_dialogs.dart';

export '../widgets/github_setup_onboarding.dart' show AgentReadinessCard;

class GitHubSetupScreen extends StatefulWidget {
  const GitHubSetupScreen({
    required this.controller,
    required this.repository,
    required this.step,
    required this.onRepositoryChanged,
    required this.onStepChanged,
    required this.onOpenWorkshop,
    super.key,
  });

  final AppController controller;
  final String? repository;
  final String? step;
  final ValueChanged<String?> onRepositoryChanged;
  final ValueChanged<String> onStepChanged;
  final VoidCallback onOpenWorkshop;

  @override
  State<GitHubSetupScreen> createState() => _GitHubSetupScreenState();
}

class _GitHubSetupScreenState extends State<GitHubSetupScreen>
    with WidgetsBindingObserver {
  static const _readinessTimeout = Duration(seconds: 15);

  GitHubSetupReadinessModel? _readiness;
  String? _readinessError;
  bool _checking = true;
  bool _actionInProgress = false;

  String? get _repository {
    final repositories = widget.controller.workspace!.repositories;
    return repositories.contains(widget.repository)
        ? widget.repository
        : repositories.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReadiness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) {
      _loadReadiness(announceProgress: true);
    }
  }

  Future<void> _loadReadiness({bool announceProgress = false}) async {
    final wasReady = _readiness?.readyFor(_repository ?? '') == true;
    setState(() {
      _checking = true;
      _readinessError = null;
    });
    try {
      final response = await widget.controller.api
          .get('v1/workspaces/${widget.controller.workspace!.id}/github-setup')
          .timeout(
            _readinessTimeout,
            onTimeout: () => throw const ApiFailure(
              'github_setup_check_timeout',
              'The GitHub connection check did not start in time. Try again. No workflow or runner was started.',
            ),
          );
      final readiness = GitHubSetupReadinessModel.fromJson(response);
      if (!mounted) return;
      setState(() => _readiness = readiness);
      _syncCanonicalStep(readiness);
      if (announceProgress &&
          !wasReady &&
          readiness.readyFor(_repository ?? '')) {
        _notify('GitHub connection verified.');
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _readiness = null;
        _readinessError = error.toString();
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _syncCanonicalStep(GitHubSetupReadinessModel readiness) {
    final stages = readiness.stagesFor(_repository ?? '');
    if (stages.isEmpty) return;
    final complete = stages.every((stage) => stage.ready);
    final requestedIndex = stages.indexWhere(
      (stage) => stage.id == widget.step,
    );
    final requestedIsAvailable =
        requestedIndex >= 0 &&
        stages.take(requestedIndex).every((stage) => stage.ready);
    final canonical = complete
        ? 'complete'
        : requestedIsAvailable
        ? stages[requestedIndex].id
        : stages.where((stage) => !stage.ready).first.id;
    if (widget.step == canonical) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStepChanged(canonical);
    });
  }

  String? _blockedReason(GitHubSetupAction action) {
    if (action == GitHubSetupAction.configureRepository &&
        widget.controller.workspace!.resourceGrantVersion == 1) {
      return 'GitHub access is inherited from the organization. Use Workspace access to change the App or repository subset.';
    }
    if (action != GitHubSetupAction.configureRepository ||
        widget.controller.can('workspace.manage')) {
      return null;
    }
    return 'Your account can\u2019t change workspace settings. Ask a workspace admin to connect the installation and repository.';
  }

  Future<void> _handleAction(
    GitHubSetupAction action,
    GitHubSetupCheckModel task,
  ) async {
    if (_blockedReason(action) != null) return;
    switch (action) {
      case GitHubSetupAction.configureRepository:
        await _configureRepository();
      case GitHubSetupAction.configureGitHubApp:
        await _openGitHubAppSettings();
      case GitHubSetupAction.refresh:
        await _loadReadiness(announceProgress: true);
    }
  }

  Future<void> _configureRepository() async {
    final workspace = widget.controller.workspace!;
    final input = await showRepositoryConnectionDialog(
      context,
      installationId: workspace.githubInstallationId,
      repository: _repository,
    );
    if (input == null || !mounted) return;
    await _runAction(() async {
      await widget.controller.api.patch(
        'v1/workspaces/${workspace.id}',
        body: {
          'githubInstallationId': input.installationId,
          'repositories': {
            ...workspace.repositories,
            input.repository,
          }.toList(),
        },
      );
      await widget.controller.refresh();
      widget.onRepositoryChanged(input.repository);
      await _loadReadiness();
      _notify('Connection saved and checked directly with GitHub.');
    });
  }

  Future<void> _openGitHubAppSettings() async {
    final repository = _repository;
    final owner = repository?.split('/').first;
    final exact = Uri.tryParse(_readiness?.githubAppSettingsUrl ?? '');
    final uri = exact != null && exact.host == 'github.com'
        ? exact
        : owner != null
        ? Uri.https('github.com', '/organizations/$owner/settings/apps')
        : Uri.https('github.com', '/settings/apps');
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Connect GitHub',
    subtitle:
        'Connect the App, verify the three required permissions, and review deployment verification.',
    child: AgentReadinessCard(
      readiness: _readiness,
      repository: _repository,
      repositories: widget.controller.workspace!.repositories,
      step: widget.step,
      loading: _checking,
      error: _readinessError,
      actionInProgress: _actionInProgress,
      blockedReason: _blockedReason,
      onRepositoryChanged: widget.onRepositoryChanged,
      onStepChanged: widget.onStepChanged,
      onAction: _handleAction,
      onOpenWorkshop: widget.onOpenWorkshop,
      onRefresh: () => _loadReadiness(announceProgress: true),
    ),
  );
}

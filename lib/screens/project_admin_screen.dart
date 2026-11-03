import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/prompt_enhancement_settings_change.dart';
import '../repositories/github_project_repository.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/data_plane_status.dart';
import '../widgets/prompt_enhancement_editor.dart';
import '../widgets/workflow_catalog_editor.dart';
import '../widgets/workflow_token_editor.dart';
import 'github_project_picker_dialog.dart';

part 'project_admin_editors.dart';
part 'project_admin_setup_overview.dart';

final _googleSecretVersionResource = RegExp(
  r'^projects/[A-Za-z0-9][A-Za-z0-9._-]{0,127}/secrets/'
  r'[A-Za-z0-9_-]{1,255}/versions/(?:latest|[1-9][0-9]*)$',
);

class ProjectAdminScreen extends StatefulWidget {
  const ProjectAdminScreen({
    required this.controller,
    this.pageActions = const [],
    this.onManageOrganizationResources,
    this.onManageWorkspaceAccess,
    this.onOpenGitHubSetup,
    this.githubProjects,
    super.key,
  });

  final AppController controller;
  final List<Widget> pageActions;
  final VoidCallback? onManageOrganizationResources;
  final VoidCallback? onManageWorkspaceAccess;
  final VoidCallback? onOpenGitHubSetup;
  final GitHubProjectRepository? githubProjects;

  @override
  State<ProjectAdminScreen> createState() => _ProjectAdminScreenState();
}

class _ProjectAdminScreenState extends State<ProjectAdminScreen> {
  late final TextEditingController _name;
  late final TextEditingController _deepSeekSecretVersion;
  late final TextEditingController _deepSeekApiKey;
  late PromptEnhancementKeySource _deepSeekKeySource;
  late String _deepSeekKeyLast4;
  bool _removeDeepSeekKey = false;
  late List<String> _repositories;
  late List<String> _workflows;
  late List<ProjectConnection> _projects;
  late String _environment;
  late bool _promptEnhancementEnabled;
  Timer? _autosaveTimer;
  bool _saving = false;
  int _changeRevision = 0;
  final Map<String, int> _dirtyKeyRevisions = {};
  String? _saveError;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final workspace = widget.controller.workspace!;
    _name = TextEditingController(text: workspace.name);
    _deepSeekSecretVersion = TextEditingController(
      text: workspace.promptEnhancement?.apiKeySecretVersion ?? '',
    );
    _repositories = [...workspace.repositories];
    _workflows = [...workspace.workflows];
    _projects = [...workspace.projects];
    _environment = workspace.environment;
    _promptEnhancementEnabled = workspace.promptEnhancement?.enabled ?? false;
    _deepSeekApiKey = TextEditingController();
    _deepSeekKeyLast4 = workspace.promptEnhancement?.apiKeyLast4 ?? '';
    // Default to the source already in use, so opening Settings never looks
    // like the credential moved.
    _deepSeekKeySource =
        (workspace.promptEnhancement?.apiKeySecretVersion ?? '').isNotEmpty &&
            !(workspace.promptEnhancement?.hasApiKey ?? false)
        ? PromptEnhancementKeySource.secretManager
        : PromptEnhancementKeySource.pasted;
    _name.addListener(_nameChanged);
    _deepSeekSecretVersion.addListener(_promptEnhancementChanged);
    _deepSeekApiKey.addListener(_promptEnhancementChanged);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _name.removeListener(_nameChanged);
    _deepSeekSecretVersion.removeListener(_promptEnhancementChanged);
    _deepSeekApiKey.removeListener(_promptEnhancementChanged);
    _name.dispose();
    _deepSeekSecretVersion.dispose();
    _deepSeekApiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Workspace setup',
      subtitle:
          'Resources, workflows, and project tools · Changes save automatically',
      actions: [
        ...widget.pageActions,
        _AutosaveStatus(
          saving: _saving,
          pending: _dirtyKeyRevisions.isNotEmpty,
          validationError: _validationError,
          saveError: _saveError,
          onRetry: _retrySave,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataPlaneStatusPanel(controller: widget.controller),
          IiOsGap.vMd,
          _WorkspaceSetupOverview(
            onManageOrganizationResources: widget.onManageOrganizationResources,
            onManageWorkspaceAccess: widget.onManageWorkspaceAccess,
          ),
          IiOsGap.vMd,
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Workspace'),
                  IiOsGap.vMd,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      final name = TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
                      );
                      final environment = SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'dev', label: Text('Dev')),
                          ButtonSegment(value: 'prod', label: Text('Prod')),
                        ],
                        selected: {_environment},
                        onSelectionChanged: (value) {
                          if (_environment == value.first) return;
                          _environment = value.first;
                          _settingsChanged('environment', immediate: true);
                        },
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [name, IiOsGap.vSm, environment],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: name),
                          IiOsGap.hMd,
                          environment,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          IiOsGap.vMd,
          if (widget.controller.workspace!.resourceGrantVersion != 1) ...[
            _LegacyGitHubConnection(
              repositories: _repositories,
              onOpenGitHubSetup: widget.onOpenGitHubSetup,
            ),
            IiOsGap.vMd,
          ],
          WorkflowCatalogEditor(
            controller: widget.controller,
            selected: _workflows,
            onManageWorkspaceAccess: widget.onManageWorkspaceAccess,
            onChanged: (value) {
              _workflows = value;
              _settingsChanged('workflows', immediate: true);
            },
          ),
          IiOsGap.vMd,
          _ProjectListEditor(
            workspaceId: widget.controller.workspace!.id,
            repositories: _repositories,
            projects: _projects,
            repository:
                widget.githubProjects ??
                GitHubProjectApiRepository(widget.controller.api),
            onChanged: (value) {
              _projects = value;
              _settingsChanged('projects', immediate: true);
            },
          ),
          IiOsGap.vMd,
          PromptEnhancementEditor(
            enabled: _promptEnhancementEnabled,
            keySource: _deepSeekKeySource,
            secretVersionController: _deepSeekSecretVersion,
            apiKeyController: _deepSeekApiKey,
            installedKeyLast4: _removeDeepSeekKey ? '' : _deepSeekKeyLast4,
            onKeySourceChanged: (value) {
              if (_deepSeekKeySource == value) return;
              _deepSeekKeySource = value;
              _settingsChanged('promptEnhancement', immediate: true);
            },
            onRemoveKey: () {
              _removeDeepSeekKey = true;
              _deepSeekApiKey.clear();
              _settingsChanged('promptEnhancement', immediate: true);
            },
            onEnabledChanged: (value) {
              if (_promptEnhancementEnabled == value) return;
              _promptEnhancementEnabled = value;
              _settingsChanged('promptEnhancement', immediate: true);
            },
          ),
          IiOsGap.vMd,
          WorkflowTokenEditor(controller: widget.controller),
        ],
      ),
    );
  }

  void _nameChanged() => _settingsChanged('name');

  void _promptEnhancementChanged() => _settingsChanged('promptEnhancement');

  void _settingsChanged(String key, {bool immediate = false}) {
    if (!mounted) return;
    _autosaveTimer?.cancel();
    setState(() {
      _changeRevision += 1;
      _dirtyKeyRevisions[key] = _changeRevision;
      _saveError = null;
      _validationError = _settingsValidationError();
    });
    if (_validationError != null || _saving) return;
    _scheduleSave(immediate: immediate);
  }

  void _scheduleSave({bool immediate = false}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 650),
      () {
        _autosaveTimer = null;
        unawaited(_save());
      },
    );
  }

  String? _settingsValidationError() {
    if (_name.text.trim().isEmpty) return 'Add a workspace name to save.';
    final secretVersion = _deepSeekSecretVersion.text.trim();
    if (secretVersion.isNotEmpty &&
        !_googleSecretVersionResource.hasMatch(secretVersion)) {
      return 'Use a complete Google Secret Manager version resource.';
    }
    if (_promptEnhancementEnabled && !_hasDeepSeekCredential) {
      return _deepSeekKeySource == PromptEnhancementKeySource.pasted
          ? 'Paste a DeepSeek API key to turn prompt enhancement on.'
          : 'Add a DeepSeek API key secret version to save.';
    }
    return null;
  }

  /// True when saving would leave the project with a usable DeepSeek key.
  ///
  /// A stored key counts even though the form cannot show it -- the field is
  /// empty because ii-os never hands a key back, not because there is none.
  bool get _hasDeepSeekCredential => switch (_deepSeekKeySource) {
    PromptEnhancementKeySource.pasted =>
      _deepSeekApiKey.text.trim().isNotEmpty ||
          (_deepSeekKeyLast4.isNotEmpty && !_removeDeepSeekKey),
    PromptEnhancementKeySource.secretManager =>
      _deepSeekSecretVersion.text.trim().isNotEmpty,
  };

  Map<String, Object?> _workspaceChanges(Set<String> keys) {
    return {
      if (keys.contains('name')) 'name': _name.text.trim(),
      if (keys.contains('environment')) 'environment': _environment,
      if (keys.contains('projects'))
        'projects': _projects.map((project) => project.toJson()).toList(),
      if (keys.contains('workflows')) 'workflows': [..._workflows],
      if (keys.contains('promptEnhancement'))
        'promptEnhancement': promptEnhancementSettingsChange(
          enabled: _promptEnhancementEnabled,
          usesSecretManager:
              _deepSeekKeySource == PromptEnhancementKeySource.secretManager,
          secretVersion: _deepSeekSecretVersion.text,
          pastedApiKey: _deepSeekApiKey.text,
          hasStoredPastedKey: _deepSeekKeyLast4.isNotEmpty,
          removeStoredPastedKey: _removeDeepSeekKey,
        ),
    };
  }

  Future<void> _save() async {
    if (!mounted || _saving || _dirtyKeyRevisions.isEmpty) return;
    final validationError = _settingsValidationError();
    if (validationError != null) {
      setState(() => _validationError = validationError);
      return;
    }
    final savingRevision = _changeRevision;
    final savingKeyRevisions = {..._dirtyKeyRevisions};
    final workspaceId = widget.controller.workspace!.id;
    final changes = _workspaceChanges(savingKeyRevisions.keys.toSet());
    setState(() => _saving = true);
    try {
      await widget.controller.api.patch(
        'v1/workspaces/$workspaceId',
        body: changes,
      );
      _acceptSavedPromptEnhancementDraft(changes, savingKeyRevisions);
      await widget.controller.refresh();
      if (mounted) {
        setState(() {
          for (final entry in savingKeyRevisions.entries) {
            if (_dirtyKeyRevisions[entry.key] == entry.value) {
              _dirtyKeyRevisions.remove(entry.key);
            }
          }
          _saveError = null;
          _validationError = _settingsValidationError();
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_changeRevision > savingRevision &&
            _dirtyKeyRevisions.isNotEmpty &&
            _validationError == null) {
          _scheduleSave();
        }
      }
    }
  }

  void _acceptSavedPromptEnhancementDraft(
    Map<String, Object?> changes,
    Map<String, int> savingKeyRevisions,
  ) {
    final savedRevision = savingKeyRevisions['promptEnhancement'];
    final change = changes['promptEnhancement'];
    if (!mounted ||
        savedRevision == null ||
        _dirtyKeyRevisions['promptEnhancement'] != savedRevision ||
        change is! Map<String, Object?>) {
      return;
    }
    final savedApiKey = (change['apiKey'] as String? ?? '').trim();
    setState(() {
      _deepSeekKeyLast4 = installedPastedKeyLast4AfterSave(
        change,
        current: _deepSeekKeyLast4,
      );
      _removeDeepSeekKey = false;
      if (savedApiKey.isNotEmpty) {
        // Clearing the accepted plaintext must not schedule another save.
        _deepSeekApiKey.removeListener(_promptEnhancementChanged);
        _deepSeekApiKey.clear();
        _deepSeekApiKey.addListener(_promptEnhancementChanged);
      }
    });
  }

  void _retrySave() {
    if (_saving) return;
    setState(() {
      _saveError = null;
      _validationError = _settingsValidationError();
    });
    if (_validationError == null) _scheduleSave(immediate: true);
  }
}

class _AutosaveStatus extends StatelessWidget {
  const _AutosaveStatus({
    required this.saving,
    required this.pending,
    required this.validationError,
    required this.saveError,
    required this.onRetry,
  });

  final bool saving;
  final bool pending;
  final String? validationError;
  final String? saveError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const _AutosaveLabel(
        label: 'Saving\u2026',
        progress: true,
        icon: LucideIcons.clock3,
      );
    }
    if (saveError case final error?) {
      return Tooltip(
        message: error,
        child: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.triangleAlert, size: 17),
          label: const Text('Save failed · Retry'),
        ),
      );
    }
    if (validationError case final error?) {
      return Tooltip(
        message: error,
        child: const _AutosaveLabel(
          label: 'Needs attention',
          icon: LucideIcons.triangleAlert,
        ),
      );
    }
    return _AutosaveLabel(
      label: pending ? 'Saving soon\u2026' : 'Saved automatically',
      icon: pending ? LucideIcons.clock3 : LucideIcons.circleCheck,
    );
  }
}

class _AutosaveLabel extends StatelessWidget {
  const _AutosaveLabel({
    required this.label,
    required this.icon,
    this.progress = false,
  });

  final String label;
  final IconData icon;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 17),
          const SizedBox(width: 7),
          Text(label),
        ],
      ),
    );
  }
}

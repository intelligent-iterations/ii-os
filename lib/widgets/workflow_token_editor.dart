import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import 'common.dart';

class WorkflowTokenEditor extends StatefulWidget {
  const WorkflowTokenEditor({required this.controller, super.key});

  final AppController controller;

  @override
  State<WorkflowTokenEditor> createState() => _WorkflowTokenEditorState();
}

class _WorkflowTokenEditorState extends State<WorkflowTokenEditor> {
  List<JsonMap> _credentials = const [];
  bool _loading = true;
  bool _mutating = false;

  String get _base =>
      'v1/workspaces/${widget.controller.workspace!.id}/workflow-tokens';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'Machine API credentials',
              trailing: IconButton.filledTonal(
                tooltip: 'Create machine API credential',
                onPressed: _mutating ? null : _create,
                icon: const Icon(LucideIcons.plus, size: 18),
              ),
            ),
            IiOsGap.vXxs,
            Text(
              'For AI agents and workspace-owned workflows. People join with '
              'an email invitation instead.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vSm,
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_credentials.isEmpty)
              const EmptyState(
                title: 'No machine API credentials',
                message: 'None configured for this workspace.',
                icon: LucideIcons.keyRound,
              )
            else
              for (var index = 0; index < _credentials.length; index++) ...[
                _CredentialTile(
                  credential: _credentials[index],
                  disabled: _mutating,
                  onRotate: () => _rotate(_credentials[index]),
                  onRevoke: () => _revoke(_credentials[index]),
                ),
                if (index < _credentials.length - 1) const Divider(),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final response = await widget.controller.api.get(_base);
      final credentials =
          (response['credentials'] as List<Object?>? ?? const [])
              .map(asJsonMap)
              .toList();
      if (mounted) setState(() => _credentials = credentials);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final request = await showDialog<_CredentialRequest>(
      context: context,
      builder: (context) => _CreateCredentialDialog(
        repositories: widget.controller.workspace!.repositories,
      ),
    );
    if (request == null) return;
    await _mutate(() async {
      final response = await widget.controller.api.post(
        _base,
        body: {
          'repository': request.repository,
          'expiresInDays': request.expiresInDays,
        },
      );
      await _showIssued(asJsonMap(response['data']));
    });
  }

  Future<void> _rotate(JsonMap credential) async {
    await _mutate(() async {
      final response = await widget.controller.api.post(
        '$_base/${credential['id']}/rotate',
        body: const {'expiresInDays': 90},
      );
      await _showIssued(asJsonMap(response['data']));
    });
  }

  Future<void> _revoke(JsonMap credential) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke credential'),
        content: Text(credential['repository']?.toString() ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _mutate(() async {
      await widget.controller.api.delete('$_base/${credential['id']}');
    });
  }

  Future<void> _mutate(Future<void> Function() action) async {
    setState(() => _mutating = true);
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _showIssued(JsonMap data) async {
    final token = data['token'] as String? ?? '';
    if (!mounted || token.isEmpty) return;
    final connectorUrl =
        '${widget.controller.connection!.webOrigin.replaceFirst(RegExp(r'/$'), '')}/api';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub Actions setup'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IssuedSetting(
                kind: 'REPOSITORY SECRET',
                name: 'II_OS_TOKEN',
                value: token,
              ),
              IiOsGap.vMd,
              _IssuedSetting(
                kind: 'REPOSITORY VARIABLE',
                name: 'II_OS_CONNECTOR_URL',
                value: connectorUrl,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy setup values',
            onPressed: () => Clipboard.setData(
              ClipboardData(
                text: 'II_OS_TOKEN=$token\nII_OS_CONNECTOR_URL=$connectorUrl',
              ),
            ),
            icon: const Icon(LucideIcons.copy, size: 18),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _IssuedSetting extends StatelessWidget {
  const _IssuedSetting({
    required this.kind,
    required this.name,
    required this.value,
  });

  final String kind;
  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kind, style: Theme.of(context).textTheme.labelSmall),
        IiOsGap.vXxs,
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy $name',
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
              icon: const Icon(LucideIcons.copy, size: 17),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 110),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(5),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _CredentialTile extends StatelessWidget {
  const _CredentialTile({
    required this.credential,
    required this.disabled,
    required this.onRotate,
    required this.onRevoke,
  });

  final JsonMap credential;
  final bool disabled;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final status = credential['status']?.toString() ?? 'unknown';
    final active = status == 'active';
    final revoked = status == 'revoked';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(LucideIcons.keyRound, size: 19),
      title: Text(credential['repository']?.toString() ?? 'Repository'),
      subtitle: Text('Expires ${_shortDate(credential['expiresAt'])}'),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusPill(status),
          IconButton(
            tooltip: 'Rotate credential',
            onPressed: disabled || !active ? null : onRotate,
            icon: const Icon(LucideIcons.refreshCw, size: 17),
          ),
          IconButton(
            tooltip: 'Revoke credential',
            onPressed: disabled || revoked ? null : onRevoke,
            icon: const Icon(LucideIcons.trash2, size: 17),
          ),
        ],
      ),
    );
  }
}

class _CreateCredentialDialog extends StatefulWidget {
  const _CreateCredentialDialog({required this.repositories});

  final List<String> repositories;

  @override
  State<_CreateCredentialDialog> createState() =>
      _CreateCredentialDialogState();
}

class _CreateCredentialDialogState extends State<_CreateCredentialDialog> {
  String? _repository;
  int _expiresInDays = 90;

  @override
  void initState() {
    super.initState();
    _repository = widget.repositories.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create machine API credential'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _repository,
              decoration: const InputDecoration(labelText: 'Repository'),
              items: widget.repositories
                  .map(
                    (repository) => DropdownMenuItem(
                      value: repository,
                      child: Text(repository),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _repository = value),
            ),
            IiOsGap.vSm,
            DropdownButtonFormField<int>(
              initialValue: _expiresInDays,
              decoration: const InputDecoration(labelText: 'Expiry'),
              items: const [30, 90, 180, 365]
                  .map(
                    (days) => DropdownMenuItem(
                      value: days,
                      child: Text('$days days'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _expiresInDays = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _repository == null
              ? null
              : () => Navigator.pop(
                  context,
                  _CredentialRequest(_repository!, _expiresInDays),
                ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

final class _CredentialRequest {
  const _CredentialRequest(this.repository, this.expiresInDays);

  final String repository;
  final int expiresInDays;
}

String _shortDate(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? 'unknown'
      : parsed.toLocal().toIso8601String().split('T').first;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

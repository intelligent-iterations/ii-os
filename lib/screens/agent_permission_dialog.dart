import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/agent_permission.dart';
import '../models/models.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

/// Review what an agent may do in your repository, then install it.
///
/// This dialog used to be a bare textarea titled "Agent permission JSON",
/// opening on `schema_version`, an image digest, `ram_mb`, and a capability
/// list. The decision it asks for -- how much authority to hand an agent over
/// your own code -- is one an owner has to be able to make, and nobody makes it
/// by reading a container digest.
///
/// The profile already carries the answer: `allowed_actions` and
/// `denied_actions` are plain sentences. They lead. Runtime, image, resources,
/// and credential bindings are how the boundary is enforced rather than what it
/// is, so they sit in a collapsed disclosure, and the raw document stays one
/// click away for whoever is authoring a profile rather than approving one.
class AgentPermissionDialog extends StatefulWidget {
  const AgentPermissionDialog({required this.initial, super.key});

  final JsonMap initial;

  @override
  State<AgentPermissionDialog> createState() => _AgentPermissionDialogState();
}

class _AgentPermissionDialogState extends State<AgentPermissionDialog> {
  late JsonMap _profile = widget.initial;
  late final TextEditingController _source = TextEditingController(
    text: _encode(widget.initial),
  );
  bool _editingJson = false;
  String? _error;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final profile = AgentPermissionModel(_profile);
    return Dialog(
      insetPadding: const EdgeInsets.all(IiOsSpacing.md),
      // The summary shrink-wraps: a profile with four allowed and four denied
      // actions is short, and a fixed 86%-of-viewport box left two thirds of
      // the dialog empty below the content. The editor keeps a tall box,
      // because a JSON document needs room to be read.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: _editingJson ? size.height * _dialogHeightFraction : 0,
          maxHeight: size.height * _dialogHeightFraction,
        ),
        child: SizedBox(
          width: _dialogWidth,
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _editingJson
                      ? 'Agent permission JSON'
                      : profile.displayName.isEmpty
                      ? 'Agent permissions'
                      : profile.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IiOsGap.vSm,
                Flexible(
                  child: _editingJson
                      ? _JsonEditor(controller: _source, error: _error)
                      : _PermissionSummary(profile: profile),
                ),
                IiOsGap.vSm,
                _DialogActions(
                  editingJson: _editingJson,
                  onToggle: _toggle,
                  onCancel: () => Navigator.pop(context),
                  onSubmit: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Switches between the two views, carrying edits across.
  ///
  /// Leaving the editor re-parses first: a summary rendered from the profile
  /// the user just stopped editing would show them the old boundary while the
  /// install button sent the new one.
  void _toggle() {
    if (!_editingJson) {
      setState(() {
        _source.text = _encode(_profile);
        _error = null;
        _editingJson = true;
      });
      return;
    }
    final parsed = _parse();
    if (parsed == null) return;
    setState(() {
      _profile = parsed;
      _editingJson = false;
      _error = null;
    });
  }

  void _submit() {
    if (!_editingJson) {
      Navigator.pop(context, _profile);
      return;
    }
    final parsed = _parse();
    if (parsed == null) return;
    Navigator.pop(context, parsed);
  }

  /// The editor's text as a profile, or null after showing why it is not one.
  JsonMap? _parse() {
    try {
      final value = jsonDecode(_source.text);
      if (value is! Map<String, Object?>) {
        throw const FormatException('The profile must be a JSON object.');
      }
      return value;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return null;
    }
  }
}

String _encode(JsonMap json) =>
    const JsonEncoder.withIndent('  ').convert(json);

/// Wide enough for a permission sentence to sit on one line, and tall enough
/// that both action lists and the disclosure are visible without scrolling.
const _dialogWidth = 760.0;
const _dialogHeightFraction = 0.86;

/// The label column in the runtime disclosure, sized to "Protected environment".
const _factLabelWidth = 168.0;

class _PermissionSummary extends StatelessWidget {
  const _PermissionSummary({required this.profile});

  final AgentPermissionModel profile;

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    children: [
      if (profile.description.isNotEmpty) ...[
        Text(profile.description, style: Theme.of(context).textTheme.bodyLarge),
        IiOsGap.vLg,
      ],
      _ActionList(
        title: 'In your repository, this agent can',
        actions: profile.allowedActions,
        icon: LucideIcons.check,
        color: IiOsColors.green,
        emptyMessage: 'This profile grants no actions.',
      ),
      IiOsGap.vLg,
      _ActionList(
        title: 'It cannot',
        actions: profile.deniedActions,
        icon: LucideIcons.minus,
        color: IiOsColors.red,
        emptyMessage: 'This profile names nothing it refuses.',
      ),
      IiOsGap.vLg,
      _RuntimeDisclosure(profile: profile),
    ],
  );
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.title,
    required this.actions,
    required this.icon,
    required this.color,
    required this.emptyMessage,
  });

  final String title;
  final List<String> actions;
  final IconData icon;
  final Color color;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      IiOsGap.vXs,
      if (actions.isEmpty)
        Text(emptyMessage, style: Theme.of(context).textTheme.bodySmall)
      else
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(top: IiOsSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: color),
                IiOsGap.hXs,
                Expanded(child: Text(action)),
              ],
            ),
          ),
    ],
  );
}

/// How the boundary above is enforced.
///
/// Collapsed because it answers a different question than the one the dialog
/// asks. An owner approving a profile needs the two lists; whoever is debugging
/// why a run behaved a certain way needs this, and can open it.
class _RuntimeDisclosure extends StatelessWidget {
  const _RuntimeDisclosure({required this.profile});

  final AgentPermissionModel profile;

  @override
  Widget build(BuildContext context) {
    final facts = <(String, String)>[
      if (profile.workflowRef.isNotEmpty) ('Branch', profile.workflowRef),
      if (profile.runtimeKind.isNotEmpty) ('Runtime', profile.runtimeKind),
      if (profile.runtimeConfigurationReference.isNotEmpty)
        ('Configuration', profile.runtimeConfigurationReference),
      if (profile.runtimeBindingReference.isNotEmpty)
        ('Execution binding', profile.runtimeBindingReference),
      if (profile.environment.isNotEmpty)
        ('Protected environment', profile.environment),
      if (profile.image.isNotEmpty) ('Image', profile.image),
      if (profile.capabilities.isNotEmpty)
        ('Capabilities', profile.capabilities.join(', ')),
      if (profile.version.isNotEmpty) ('Profile version', profile.version),
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(LucideIcons.settings2, size: 18),
      title: const Text('Runtime details'),
      subtitle: const Text('How this boundary is enforced'),
      children: [
        for (final (label, value) in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _factLabelWidth,
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: IiOsColors.muted),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (profile.secretBindings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: IiOsSpacing.xxs),
            child: Text(
              'Credentials are read from your repository\u2019s secrets at run time '
              'and are never returned to ii-os.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: IiOsColors.muted),
            ),
          ),
      ],
    );
  }
}

class _JsonEditor extends StatelessWidget {
  const _JsonEditor({required this.controller, required this.error});

  final TextEditingController controller;
  final String? error;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    expands: true,
    minLines: null,
    maxLines: null,
    keyboardType: TextInputType.multiline,
    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    decoration: InputDecoration(
      alignLabelWithHint: true,
      labelText: 'Agent permission template',
      errorText: error,
    ),
  );
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.editingJson,
    required this.onToggle,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool editingJson;
  final VoidCallback onToggle;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.end,
    children: [
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
      TextButton.icon(
        onPressed: onToggle,
        icon: Icon(
          editingJson ? LucideIcons.listChecks : LucideIcons.code,
          size: 17,
        ),
        label: Text(editingJson ? 'Back to summary' : 'Edit as JSON'),
      ),
      FilledButton.icon(
        onPressed: onSubmit,
        icon: const Icon(LucideIcons.workflow, size: 17),
        label: const Text('Install these permissions'),
      ),
    ],
  );
}

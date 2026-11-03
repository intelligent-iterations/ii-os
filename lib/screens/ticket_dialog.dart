import 'package:flutter/material.dart';

import '../models/agent_permission.dart';
import '../models/models.dart';
import '../models/ticket.dart';
import '../models/workshop_ticket_draft.dart';
import '../theme/ii_os_tokens.dart';

class TicketDialog extends StatefulWidget {
  const TicketDialog({
    required this.heading,
    required this.repository,
    required this.permissionProfiles,
    super.key,
    this.draft,
    this.initial,
    this.projectId,
    this.projects = const [],
    this.initialPermissionProfile,
  });

  final String heading;
  final String repository;
  final WorkshopTicketDraft? draft;
  final TicketModel? initial;
  final String? projectId;
  final List<ProjectConnection> projects;
  final List<AgentPermissionModel> permissionProfiles;
  final String? initialPermissionProfile;

  @override
  State<TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<TicketDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.title ?? widget.draft?.title ?? '',
  );
  late final TextEditingController _definitionOfDone = TextEditingController(
    text:
        widget.initial?.definitionOfDone ??
        widget.draft?.definitionOfDone ??
        '',
  );
  late final TextEditingController _howToTest = TextEditingController(
    text: widget.initial?.howToTest ?? widget.draft?.howToTest ?? '',
  );
  late final TextEditingController _permissionRef = TextEditingController(
    text:
        widget.initial?.permissionRef ??
        widget.draft?.permissionRef ??
        widget.permissionProfiles.firstOrNull?.workflowRef ??
        'dev',
  );
  late String _state = widget.initial?.state ?? 'open';
  late String _permissionProfile =
      widget.initial?.permissionProfile ??
      widget.draft?.permissionProfile ??
      widget.initialPermissionProfile ??
      widget.permissionProfiles.firstOrNull?.id ??
      'none';
  late String? _projectId = widget.initial == null
      ? widget.draft?.projectId ??
            widget.projectId ??
            widget.projects.firstOrNull?.id
      : null;

  @override
  void dispose() {
    _title.dispose();
    _definitionOfDone.dispose();
    _howToTest.dispose();
    _permissionRef.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 620;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? IiOsSpacing.sm : IiOsSpacing.xl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: size.height * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? IiOsSpacing.md : IiOsSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.heading,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IiOsGap.vXxs,
                Text(
                  widget.repository,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                IiOsGap.vMd,
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: IiOsSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _title,
                          maxLength: 256,
                          decoration: const InputDecoration(
                            labelText: 'What needs to change?',
                            helperText:
                                'A short, outcome-focused ticket title.',
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _definitionOfDone,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Definition of Done',
                            helperText:
                                'Observable results the agent must deliver.',
                            alignLabelWithHint: true,
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _howToTest,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'How will we verify it?',
                            helperText:
                                'Tests, commands, and live checks required before QA.',
                            alignLabelWithHint: true,
                          ),
                          validator: _required,
                        ),
                        if (widget.draft?.context.trim().isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 10),
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Additional context',
                            ),
                            child: SelectableText(widget.draft!.context.trim()),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _permissionFields(compact),
                        IiOsGap.vSm,
                        if (widget.initial != null)
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'open', label: Text('Open')),
                              ButtonSegment(
                                value: 'closed',
                                label: Text('Closed'),
                              ),
                            ],
                            selected: {_state},
                            onSelectionChanged: (value) =>
                                setState(() => _state = value.first),
                          ),
                        if (widget.initial == null &&
                            widget.projects.isNotEmpty) ...[
                          IiOsGap.vSm,
                          DropdownButtonFormField<String>(
                            initialValue: _projectId,
                            decoration: const InputDecoration(
                              labelText: 'Workshop Project',
                              helperText:
                                  'This Project owns status, review, and human-started deployment.',
                            ),
                            items: [
                              ...widget.projects.map(
                                (project) => DropdownMenuItem<String>(
                                  value: project.id,
                                  child: Text(
                                    project.title.isEmpty
                                        ? 'Project ${project.number}'
                                        : project.title,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _projectId = value),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Choose the Project that will manage this ticket.'
                                : null,
                          ),
                        ],
                        if (widget.initial == null) ...[
                          IiOsGap.vSm,
                          const _WorkshopHandoffNotice(),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(
                        widget.initial == null
                            ? 'Create workshop ticket'
                            : 'Save changes',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissionFields(bool compact) {
    final known = widget.permissionProfiles.map((item) => item.id).toSet();
    final options = <String>{'none', ...known, _permissionProfile};
    final profile = DropdownButtonFormField<String>(
      initialValue: _permissionProfile,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Agent engine and permissions',
      ),
      items: options
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(
                value == 'none'
                    ? 'No agent access'
                    : widget.permissionProfiles
                              .where((item) => item.id == value)
                              .firstOrNull
                              ?.selectionLabel ??
                          value,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _permissionProfile = value;
          final selected = widget.permissionProfiles
              .where((item) => item.id == value)
              .firstOrNull;
          if (selected != null) {
            _permissionRef.text = selected.workflowRef;
          }
        });
      },
    );
    final ref = TextFormField(
      controller: _permissionRef,
      decoration: const InputDecoration(labelText: 'Permission branch/ref'),
      validator: _required,
    );
    final fields = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [profile, const SizedBox(height: 10), ref],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: profile),
              const SizedBox(width: 10),
              Expanded(child: ref),
            ],
          );
    final selected = widget.permissionProfiles
        .where((item) => item.id == _permissionProfile)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fields,
        const SizedBox(height: 7),
        Text(
          selected?.description ??
              'No agent access keeps this ticket as a human-managed draft.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      TicketEditData(
        title: _title.text.trim(),
        definitionOfDone: _definitionOfDone.text.trim(),
        howToTest: _howToTest.text.trim(),
        permissionProfile: _permissionProfile,
        permissionRef: _permissionRef.text.trim(),
        context: widget.initial?.context ?? widget.draft?.context ?? '',
        state: _state,
        projectId: _projectId,
      ),
    );
  }
}

final class TicketEditData {
  const TicketEditData({
    required this.title,
    required this.definitionOfDone,
    required this.howToTest,
    required this.permissionProfile,
    required this.permissionRef,
    required this.context,
    required this.state,
    this.projectId,
  });

  final String title;
  final String definitionOfDone;
  final String howToTest;
  final String permissionProfile;
  final String permissionRef;
  final String context;
  final String state;
  final String? projectId;
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

extension _FirstTicketPermissionOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _WorkshopHandoffNotice extends StatelessWidget {
  const _WorkshopHandoffNotice();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(IiOsRadii.md),
    ),
    child: const Padding(
      padding: EdgeInsets.all(IiOsSpacing.sm),
      child: Text(
        'The ticket is not deployed when it is created. Review its readiness in Software Workshop, then press Deploy when you want it to wait for a runner.',
      ),
    ),
  );
}

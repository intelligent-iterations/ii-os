import 'package:flutter/material.dart';

import '../models/agent_permission.dart';
import '../models/models.dart';
import '../models/workshop_room.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'software_workshop_rooms.dart';

class WorkshopRoomDialog extends StatefulWidget {
  const WorkshopRoomDialog({
    required this.repositories,
    required this.projects,
    required this.permissionProfiles,
    this.initial,
    super.key,
  });

  final List<String> repositories;
  final List<ProjectConnection> projects;
  final List<AgentPermissionModel> permissionProfiles;
  final WorkshopRoomModel? initial;

  @override
  State<WorkshopRoomDialog> createState() => _WorkshopRoomDialogState();
}

class _WorkshopRoomDialogState extends State<WorkshopRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text:
        widget.initial?.name ??
        widget.projects.firstOrNull?.title ??
        _repositoryLabel(widget.repositories.firstOrNull),
  );
  late String _color = widget.initial?.color ?? 'cyan';
  late final Set<String> _repositories = {
    ...?widget.initial?.repositories,
    if (widget.initial == null && widget.repositories.isNotEmpty)
      widget.repositories.first,
  };
  late String? _projectId =
      widget.initial?.projectId ?? widget.projects.firstOrNull?.id;
  late String _permissionProfile =
      widget.initial?.permissionProfile ??
      widget.permissionProfiles.firstOrNull?.id ??
      'repository-maintainer';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Create a room' : 'Room settings'),
    content: SizedBox(
      width: IiOsBreakpoints.compact,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                  helperText: 'For example: Mobile app or Release engineering',
                ),
                validator: _required,
              ),
              IiOsGap.vSm,
              Text('Colour', style: Theme.of(context).textTheme.titleSmall),
              IiOsGap.vXs,
              Wrap(
                spacing: IiOsSpacing.xs,
                runSpacing: IiOsSpacing.xs,
                children: [
                  for (final color in workshopRoomColors)
                    ChoiceChip(
                      selected: _color == color,
                      avatar: Icon(
                        Icons.circle,
                        size: 14,
                        color: workshopRoomColor(context, color),
                      ),
                      label: Text(_capitalized(color)),
                      onSelected: (_) => setState(() => _color = color),
                    ),
                ],
              ),
              IiOsGap.vMd,
              Text(
                'GitHub repositories',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IiOsGap.vXxs,
              Text(
                'Only these repositories appear in this room.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IiOsGap.vXs,
              for (final repository in widget.repositories)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _repositories.contains(repository),
                  title: Text(repository),
                  onChanged: (selected) => setState(() {
                    selected == true
                        ? _repositories.add(repository)
                        : _repositories.remove(repository);
                  }),
                ),
              if (_repositories.isEmpty)
                Text(
                  'Choose at least one repository.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: IiOsColors.red),
                ),
              IiOsGap.vSm,
              DropdownButtonFormField<String>(
                initialValue: _projectId,
                decoration: const InputDecoration(labelText: 'GitHub Project'),
                items: widget.projects
                    .map(
                      (project) => DropdownMenuItem(
                        value: project.id,
                        child: Text(
                          project.title.isEmpty
                              ? 'Project ${project.number}'
                              : project.title,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  final previousDefault = widget.projects
                      .where((project) => project.id == _projectId)
                      .map((project) => project.title)
                      .firstOrNull;
                  final nextDefault = widget.projects
                      .where((project) => project.id == value)
                      .map((project) => project.title)
                      .firstOrNull;
                  if (_name.text.trim().isEmpty ||
                      _name.text == previousDefault) {
                    _name.text = nextDefault ?? _name.text;
                  }
                  setState(() => _projectId = value);
                },
                validator: (value) =>
                    value == null ? 'Choose a Project.' : null,
              ),
              IiOsGap.vSm,
              DropdownButtonFormField<String>(
                initialValue: _permissionProfile,
                decoration: const InputDecoration(
                  labelText: 'Default agent permissions',
                  helperText: 'Applied when a new ticket is created here.',
                ),
                items: _permissionOptions
                    .map(
                      (profile) => DropdownMenuItem(
                        value: profile,
                        child: Text(_profileName(profile)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _permissionProfile = value);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.initial == null ? 'Create room' : 'Save room'),
      ),
    ],
  );

  Set<String> get _permissionOptions => {
    'none',
    _permissionProfile,
    ...widget.permissionProfiles.map((profile) => profile.id),
  };

  String _profileName(String id) {
    if (id == 'none') return 'No agent access';
    return widget.permissionProfiles
            .where((profile) => profile.id == id)
            .map((profile) => profile.selectionLabel)
            .firstOrNull ??
        id;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false) ||
        _repositories.isEmpty ||
        _projectId == null) {
      setState(() {});
      return;
    }
    Navigator.pop(
      context,
      WorkshopRoomEditData(
        name: _name.text.trim(),
        color: _color,
        repositories: _repositories.toList()..sort(),
        projectId: _projectId!,
        permissionProfile: _permissionProfile,
      ),
    );
  }
}

final class WorkshopRoomEditData {
  const WorkshopRoomEditData({
    required this.name,
    required this.color,
    required this.repositories,
    required this.projectId,
    required this.permissionProfile,
  });

  final String name;
  final String color;
  final List<String> repositories;
  final String projectId;
  final String permissionProfile;
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

String _capitalized(String value) =>
    '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

String _repositoryLabel(String? repository) {
  final name = repository?.split('/').last ?? '';
  if (name.isEmpty) return '';
  return name
      .split(RegExp('[-_]'))
      .where((part) => part.isNotEmpty)
      .map(_capitalized)
      .join(' ');
}

extension _FirstRoomDialogOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

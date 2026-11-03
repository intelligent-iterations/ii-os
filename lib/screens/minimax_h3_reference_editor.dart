part of 'minimax_h3_generation_controls.dart';

class _ReferenceEditor extends StatefulWidget {
  const _ReferenceEditor({required this.viewModel});

  final VideoGenerationViewModel viewModel;

  @override
  State<_ReferenceEditor> createState() => _ReferenceEditorState();
}

final class _ReferenceEditorState extends State<_ReferenceEditor> {
  VideoGenerationViewModel get viewModel => widget.viewModel;

  @override
  Widget build(BuildContext context) {
    final busy = viewModel.submitting || viewModel.addingH3LibraryReference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Reference media', style: Theme.of(context).textTheme.labelLarge),
        IiOsGap.vXs,
        Text(
          viewModel.h3ReferenceRequirement,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IiOsGap.vSm,
        _ReferenceButtons(
          kinds: viewModel.allowedH3ReferenceKinds,
          busy: busy,
          onAdd: _addReference,
        ),
        if (viewModel.addingH3LibraryReference) ...[
          IiOsGap.vSm,
          const LinearProgressIndicator(
            semanticsLabel: 'Adding reference from Asset Library',
          ),
        ],
        if (viewModel.h3References.isNotEmpty) ...[
          IiOsGap.vSm,
          for (final reference in viewModel.h3References) ...[
            _ReferenceRow(
              reference: reference,
              modelLabel: viewModel.h3ReferenceLabel(reference),
              busy: busy,
              onRoleChanged: (role) =>
                  viewModel.setH3ReferenceRole(reference.id, role),
              onRemove: () => viewModel.removeH3Reference(reference.id),
            ),
            IiOsGap.vXs,
          ],
          Text(
            '${viewModel.h3References.length} of '
            '${MiniMaxH3GenerationSpec.maximumReferences} total references',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (viewModel.h3Mode == MiniMaxH3GenerationMode.videoEdit)
          _VideoEditOptions(viewModel: viewModel),
        if (viewModel.h3Mode == MiniMaxH3GenerationMode.videoContinue) ...[
          if (viewModel.supportsH3ExtensionMethod)
            _VideoContinueOptions(viewModel: viewModel),
          IiOsGap.vSm,
          const _CapabilityNotice(
            message:
                'The source must be 2\u201315 seconds and is delivered unchanged '
                'at the start, with its own sound. H3 anchors on its closing '
                'moment and renders the remaining seconds up to the duration '
                'you chose, so leave at least 2 seconds to add. Describe only '
                'what should happen next.',
          ),
        ],
        IiOsGap.vSm,
        const _CapabilityNotice(
          message:
              'Asset Library media downloads directly from workspace GCS. '
              'New uploads also go directly to that workspace bucket.',
        ),
      ],
    );
  }

  Future<void> _addReference(MiniMaxH3ReferenceKind kind) async {
    final picked = await showMediaPicker(
      context: context,
      history: viewModel.h3ReferenceHistory,
      loadPreview: viewModel.readLibraryPreview,
      contentTypePrefix: '${kind.name}/',
      title: 'Add a ${kind.name} reference',
      uploadTypes: [minimaxH3ReferenceTypeGroup(kind)],
      maxUploadBytes: _maximumBytesFor(kind),
    );
    if (picked == null || !mounted) return;
    final added = picked.isFromLibrary
        ? await viewModel.addGeneratedH3Reference(
            kind: kind,
            entry: picked.entry!,
          )
        : viewModel.addH3Reference(
            kind: kind,
            filename: picked.upload!.name,
            bytes: picked.bytes!,
          );
    if (!added && mounted) {
      showFailure(
        context,
        viewModel.modelError ??
            const FormatException('The reference media is invalid.'),
      );
    }
  }
}

class _ReferenceButtons extends StatelessWidget {
  const _ReferenceButtons({
    required this.kinds,
    required this.busy,
    required this.onAdd,
  });

  final List<MiniMaxH3ReferenceKind> kinds;
  final bool busy;
  final ValueChanged<MiniMaxH3ReferenceKind> onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IiOsSpacing.sm,
      runSpacing: IiOsSpacing.sm,
      children: [
        for (final kind in kinds)
          FilledButton.tonalIcon(
            key: ValueKey('add-h3-${kind.name}'),
            onPressed: busy ? null : () => onAdd(kind),
            icon: Icon(_iconFor(kind), size: 17),
            label: Text('Add ${kind.name}'),
          ),
      ],
    );
  }
}

class _VideoContinueOptions extends StatelessWidget {
  const _VideoContinueOptions({required this.viewModel});

  final VideoGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IiOsGap.vMd,
        DropdownButtonFormField<MiniMaxH3ExtensionMethod>(
          key: ValueKey(viewModel.h3ExtensionMethod),
          initialValue: viewModel.h3ExtensionMethod,
          decoration: const InputDecoration(
            labelText: 'How to extend',
            prefixIcon: Icon(LucideIcons.fastForward, size: 18),
          ),
          items: [
            for (final method in MiniMaxH3ExtensionMethod.values)
              DropdownMenuItem(value: method, child: Text(method.label)),
          ],
          onChanged: viewModel.submitting
              ? null
              : (value) {
                  if (value != null) viewModel.setH3ExtensionMethod(value);
                },
        ),
        IiOsGap.vXs,
        Text(
          viewModel.h3ExtensionMethod.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _VideoEditOptions extends StatelessWidget {
  const _VideoEditOptions({required this.viewModel});

  final VideoGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IiOsGap.vMd,
        DropdownButtonFormField<MiniMaxH3EditOperation>(
          key: ValueKey(viewModel.h3EditOperation),
          initialValue: viewModel.h3EditOperation,
          decoration: const InputDecoration(
            labelText: 'Edit operation',
            prefixIcon: Icon(LucideIcons.clapperboard, size: 18),
          ),
          items: [
            for (final operation in MiniMaxH3EditOperation.values)
              DropdownMenuItem(value: operation, child: Text(operation.label)),
          ],
          onChanged: viewModel.submitting
              ? null
              : (value) {
                  if (value != null) viewModel.setH3EditOperation(value);
                },
        ),
        if (viewModel.h3EditOperation ==
            MiniMaxH3EditOperation.characterReplacement) ...[
          IiOsGap.vSm,
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: viewModel.identityReplacementConsent,
            onChanged: viewModel.submitting
                ? null
                : (value) =>
                      viewModel.setIdentityReplacementConsent(value ?? false),
            title: const Text('I have permission to use this identity'),
            subtitle: const Text(
              'Required for character or face replacement. Do not use '
              'someone\u2019s likeness deceptively or without authorization.',
            ),
          ),
        ],
      ],
    );
  }
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({
    required this.reference,
    required this.modelLabel,
    required this.busy,
    required this.onRoleChanged,
    required this.onRemove,
  });

  final MiniMaxH3ReferenceDraft reference;
  final String modelLabel;
  final bool busy;
  final ValueChanged<MiniMaxH3ReferenceRole> onRoleChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final filename = Row(
      children: [
        ReferenceMediaThumbnail(
          bytes: reference.bytes,
          contentType: reference.contentType,
          icon: _iconFor(reference.kind),
        ),
        IiOsGap.hSm,
        Chip(visualDensity: VisualDensity.compact, label: Text(modelLabel)),
        IiOsGap.hSm,
        Expanded(
          child: Text(
            reference.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final remove = IconButton(
      tooltip: 'Remove ${reference.filename}',
      onPressed: busy ? null : onRemove,
      icon: const Icon(LucideIcons.trash2, size: 18),
    );
    final role = DropdownButtonFormField<MiniMaxH3ReferenceRole>(
      key: ValueKey('${reference.id}-${reference.role.name}'),
      initialValue: reference.role,
      decoration: const InputDecoration(labelText: 'Role', isDense: true),
      items: [
        for (final role in MiniMaxH3GenerationSpec.rolesFor(reference.kind))
          DropdownMenuItem(value: role, child: Text(role.label)),
      ],
      onChanged: busy
          ? null
          : (value) {
              if (value != null) onRoleChanged(value);
            },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < IiOsBreakpoints.pairedFields) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: filename),
                  remove,
                ],
              ),
              role,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: filename),
            IiOsGap.hSm,
            Flexible(child: role),
            remove,
          ],
        );
      },
    );
  }
}

IconData _iconFor(MiniMaxH3ReferenceKind kind) => switch (kind) {
  MiniMaxH3ReferenceKind.image => LucideIcons.image,
  MiniMaxH3ReferenceKind.video => LucideIcons.film,
  MiniMaxH3ReferenceKind.audio => LucideIcons.audioLines,
};

int _maximumBytesFor(MiniMaxH3ReferenceKind kind) => switch (kind) {
  MiniMaxH3ReferenceKind.image => MiniMaxH3GenerationSpec.maximumImageBytes,
  MiniMaxH3ReferenceKind.video => MiniMaxH3GenerationSpec.maximumVideoBytes,
  MiniMaxH3ReferenceKind.audio => MiniMaxH3GenerationSpec.maximumAudioBytes,
};

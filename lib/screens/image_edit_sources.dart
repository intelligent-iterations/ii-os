part of 'image_edit_panel.dart';

/// The extra pictures a multi-image edit can be steered with.
///
/// They are deliberately still called image B and image C. The instruction
/// refers to them by those names -- "make image A look like image B" -- so
/// giving them roles would make the sentence that uses them read wrong. What
/// was missing was why they do nothing on the other models, and what to do
/// about it: they used to render as two dead fields at 45% opacity, with a
/// line of copy that named a model rather than an action.
class _ReferencePictures extends StatelessWidget {
  const _ReferencePictures({
    required this.files,
    required this.bytes,
    required this.slots,
    required this.busy,
    required this.onSelect,
    required this.onClear,
  });

  final List<XFile?> files;
  final List<Uint8List?> bytes;

  /// Extra images accepted by the selected workflow contract.
  final int slots;

  final bool busy;
  final void Function(int index) onSelect;
  final void Function(int index) onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IiOsGap.vMd,
        Text(
          'Refer to these by name in the instruction \u2014 for example, \u201ckeep '
          'the subject from image A and use the setting from image B\u201d.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (var index = 0; index < slots; index++) ...[
          IiOsGap.vSm,
          SourceImageField(
            title: 'Image ${String.fromCharCode(66 + index)} · reference',
            file: files[index],
            bytes: bytes[index],
            busy: busy,
            selectLabel: 'Choose image ${String.fromCharCode(66 + index)}',
            replaceLabel: 'Replace',
            onSelect: () => onSelect(index),
            onClear: () => onClear(index),
          ),
        ],
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:ii_os_design_system/ii_os_design_system.dart' show IiOsPalette;

import '../theme/ii_os_tokens.dart';

class SourceImageField extends StatelessWidget {
  const SourceImageField({
    required this.file,
    required this.bytes,
    required this.busy,
    this.enabled = true,
    required this.onSelect,
    this.title = 'Source image',
    this.selectLabel = 'Select image',
    this.replaceLabel = 'Replace',
    this.showPreview = true,
    this.onClear,
    super.key,
  });

  final XFile? file;
  final Uint8List? bytes;
  final bool busy;
  final bool enabled;
  final VoidCallback onSelect;
  final String title;
  final String selectLabel;
  final String replaceLabel;
  final bool showPreview;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                file?.name ?? title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (file != null && onClear != null) ...[
              IconButton(
                tooltip: 'Remove image',
                onPressed: busy || !enabled ? null : onClear,
                icon: const Icon(LucideIcons.x, size: 17),
              ),
              IiOsGap.hXxs,
            ],
            OutlinedButton.icon(
              onPressed: busy || !enabled ? null : onSelect,
              icon: const Icon(LucideIcons.upload, size: 17),
              label: Text(file == null ? selectLabel : replaceLabel),
            ),
          ],
        ),
        if (showPreview && bytes != null) ...[
          IiOsGap.vSm,
          _Preview(bytes: bytes!),
        ],
      ],
    );
  }
}

/// The chosen picture, on a ground that belongs to the current mode.
///
/// This frame used to name `IiOsColors.canvas` and `IiOsColors.border`
/// directly. Those are `static const`, so in dark mode the preview sat in a
/// white box with a pale hairline around it -- right in review, wrong on screen,
/// and invisible to the analyzer.
class _Preview extends StatelessWidget {
  const _Preview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Container(
      height: _previewHeight,
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border.all(color: palette.border),
        borderRadius: IiOsRadii.mdAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.memory(bytes, fit: BoxFit.contain),
    );
  }
}

/// Tall enough to judge a photograph, short enough that the instruction below
/// it stays on the same screen.
const _previewHeight = 260.0;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/picked_media.dart';
import '../services/media_upload_reader.dart';

/// Brings a file in from the operator's own device.
///
/// The bytes are read here rather than by each caller: every one of them needs
/// them, and reading an [XFile] twice on web is a second network round trip.
class MediaUploadPane extends StatefulWidget {
  const MediaUploadPane({
    required this.types,
    required this.onPicked,
    super.key,
    this.multiple = false,
    this.maxFileBytes,
    this.maxTotalBytes,
    this.existingBytes = 0,
  });

  final List<XTypeGroup> types;
  final ValueChanged<PickedMedia> onPicked;

  final bool multiple;
  final int? maxFileBytes;
  final int? maxTotalBytes;
  final int existingBytes;

  @override
  State<MediaUploadPane> createState() => _MediaUploadPaneState();
}

class _MediaUploadPaneState extends State<MediaUploadPane> {
  bool _busy = false;
  String? _error;
  late int _pickedBytes = widget.existingBytes;

  @override
  void didUpdateWidget(MediaUploadPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.existingBytes != widget.existingBytes) {
      _pickedBytes = widget.existingBytes;
    }
  }

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = widget.multiple
          ? await openFiles(acceptedTypeGroups: widget.types)
          : [?await openFile(acceptedTypeGroups: widget.types)];
      if (files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      for (final file in files) {
        final picked = await readMediaUpload(
          file,
          pickedBytes: _pickedBytes,
          maxFileBytes: widget.maxFileBytes,
          maxTotalBytes: widget.maxTotalBytes,
        );
        if (!mounted) return;
        _pickedBytes += picked.bytes!.length;
        widget.onPicked(picked);
      }
      if (mounted && widget.multiple) setState(() => _busy = false);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message.toString();
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That file could not be read. Try another file.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: IiOsWidths.form),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.upload,
                size: IiOsIconSize.xxl,
                color: palette.muted,
              ),
              IiOsGap.vMd,
              Text(
                'Bring in your own file',
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
              IiOsGap.vXs,
              Text(
                describeAcceptedMediaTypes(widget.types),
                style: text.bodySmall?.copyWith(color: palette.muted),
                textAlign: TextAlign.center,
              ),
              IiOsGap.vLg,
              FilledButton.icon(
                onPressed: _busy ? null : _choose,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: IiOsIconSize.sm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.folderOpen, size: IiOsIconSize.sm),
                label: Text(
                  _busy
                      ? 'Reading'
                      : widget.multiple
                      ? 'Choose files'
                      : 'Choose a file',
                ),
              ),
              if (_error != null) ...[
                IiOsGap.vMd,
                InlineFormError(message: _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'pending_icon.dart';

/// A consistent local-save action for generated media surfaces.
class MediaDownloadButton extends StatefulWidget {
  const MediaDownloadButton({
    required this.onPressed,
    this.label = 'Download',
    super.key,
  });

  final Future<void> Function()? onPressed;
  final String label;

  @override
  State<MediaDownloadButton> createState() => _MediaDownloadButtonState();
}

class _MediaDownloadButtonState extends State<MediaDownloadButton> {
  bool _saving = false;

  Future<void> _save() async {
    final callback = widget.onPressed;
    if (callback == null || _saving) return;
    setState(() => _saving = true);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: _saving,
    label: _saving ? 'Saving ${widget.label.toLowerCase()}' : widget.label,
    button: true,
    child: FilledButton.icon(
      onPressed: widget.onPressed == null || _saving ? null : _save,
      icon: PendingIcon(
        icon: LucideIcons.download,
        pending: _saving,
        pendingLabel: 'Saving download',
      ),
      label: Text(_saving ? 'Saving\u2026' : widget.label),
    ),
  );
}

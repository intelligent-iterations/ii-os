import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/bug_report_client.dart';
import '../services/source_asset_uploader.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

typedef BugReportSubmitter = Future<String> Function(BugReportDraft draft);
typedef BugScreenshotPicker = Future<BugReportScreenshot?> Function();

class BugReportButton extends StatelessWidget {
  const BugReportButton({
    required this.currentRoute,
    required this.onSubmit,
    this.compact = false,
    this.pickScreenshot,
    super.key,
  });

  final String currentRoute;
  final BugReportSubmitter onSubmit;
  final bool compact;
  final BugScreenshotPicker? pickScreenshot;

  @override
  Widget build(BuildContext context) {
    void open() => showBugReportDialog(
      context: context,
      currentRoute: currentRoute,
      onSubmit: onSubmit,
      pickScreenshot: pickScreenshot,
    );

    if (compact) {
      return IconButton(
        key: const Key('bug-report-button'),
        tooltip: 'Report a bug',
        onPressed: open,
        icon: const Icon(LucideIcons.bug, size: 19),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      child: OutlinedButton.icon(
        key: const Key('bug-report-button'),
        onPressed: open,
        icon: const Icon(LucideIcons.bug, size: 17),
        label: const Text('Report a bug'),
      ),
    );
  }
}

Future<void> showBugReportDialog({
  required BuildContext context,
  required String currentRoute,
  required BugReportSubmitter onSubmit,
  BugScreenshotPicker? pickScreenshot,
}) async {
  final reportId = await showDialog<String>(
    context: context,
    builder: (context) => _BugReportDialog(
      currentRoute: currentRoute,
      onSubmit: onSubmit,
      pickScreenshot: pickScreenshot ?? _pickScreenshot,
    ),
  );
  if (reportId == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Thanks \u2014 bug report ${_shortId(reportId)} was sent.'),
    ),
  );
}

class _BugReportDialog extends StatefulWidget {
  const _BugReportDialog({
    required this.currentRoute,
    required this.onSubmit,
    required this.pickScreenshot,
  });

  final String currentRoute;
  final BugReportSubmitter onSubmit;
  final BugScreenshotPicker pickScreenshot;

  @override
  State<_BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<_BugReportDialog> {
  final _description = TextEditingController();
  final _expectedBehavior = TextEditingController();
  BugReportScreenshot? _screenshot;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _description.addListener(_refresh);
  }

  @override
  void dispose() {
    _description
      ..removeListener(_refresh)
      ..dispose();
    _expectedBehavior.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final screenshot = _screenshot;
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.bug, color: palette.danger.text, size: 21),
          const SizedBox(width: 10),
          const Flexible(child: Text('Report a bug')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell us what happened. The current screen and your account '
                'are included automatically.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.muted),
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('bug-description-field'),
                controller: _description,
                autofocus: true,
                enabled: !_busy,
                minLines: 4,
                maxLines: 7,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What went wrong?',
                  alignLabelWithHint: true,
                  hintText: 'What were you doing, and what did you see happen?',
                ),
              ),
              IiOsGap.vSm,
              TextField(
                key: const Key('bug-expected-field'),
                controller: _expectedBehavior,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What did you expect? (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              IiOsGap.vXs,
              _ScreenshotField(
                screenshot: screenshot,
                busy: _busy,
                onSelect: _selectScreenshot,
                onClear: screenshot == null
                    ? null
                    : () => setState(() => _screenshot = null),
              ),
              const SizedBox(height: 6),
              Text(
                'PNG, JPEG, or WebP · up to 10 MB · stored in this '
                'workspace\u2019s GCS bucket',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  key: const Key('bug-report-error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.danger.text),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('send-bug-report-button'),
          onPressed: _busy || _description.text.trim().isEmpty ? null : _submit,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.send, size: 17),
          label: Text(_busy ? 'Sending' : 'Send report'),
        ),
      ],
    );
  }

  Future<void> _selectScreenshot() async {
    setState(() => _error = null);
    try {
      final screenshot = await widget.pickScreenshot();
      if (screenshot != null && mounted) {
        setState(() => _screenshot = screenshot);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reportId = await widget.onSubmit(
        BugReportDraft(
          description: _description.text.trim(),
          expectedBehavior: _expectedBehavior.text.trim(),
          route: widget.currentRoute,
          clientPlatform: currentBugReportPlatform(),
          screenshot: _screenshot,
        ),
      );
      if (mounted) Navigator.pop(context, reportId);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  void _refresh() => setState(() {});
}

class _ScreenshotField extends StatelessWidget {
  const _ScreenshotField({
    required this.screenshot,
    required this.busy,
    required this.onSelect,
    required this.onClear,
  });

  final BugReportScreenshot? screenshot;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final image = screenshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                image?.filename ?? 'Screenshot (optional)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (image != null) ...[
              IconButton(
                tooltip: 'Remove screenshot',
                onPressed: busy ? null : onClear,
                icon: const Icon(LucideIcons.x, size: 17),
              ),
              IiOsGap.hXxs,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onSelect,
            icon: const Icon(LucideIcons.upload, size: 17),
            label: Text(image == null ? 'Attach screenshot' : 'Replace'),
          ),
        ),
        if (image != null) ...[
          IiOsGap.vSm,
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: palette.canvas,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(IiOsRadii.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(image.bytes, fit: BoxFit.contain),
          ),
        ],
      ],
    );
  }
}

Future<BugReportScreenshot?> _pickScreenshot() async {
  const images = XTypeGroup(
    label: 'Screenshots',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: const [images]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Choose a screenshot smaller than 10 MB.');
  }
  final contentType = sourceImageContentType(bytes);
  if (contentType == null) {
    throw const FormatException('Choose a PNG, JPEG, or WebP screenshot.');
  }
  return BugReportScreenshot(
    filename: file.name,
    bytes: Uint8List.fromList(bytes),
    contentType: contentType,
  );
}

String currentBugReportPlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'unknown',
  };
}

String _shortId(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

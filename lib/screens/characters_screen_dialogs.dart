import 'package:flutter/material.dart';

/// The prompts the characters page puts in front of a create or a delete.
///
/// Split from the page so the page file stays composition only, and so each
/// prompt is one named function a caller can read at the call site instead of
/// forty lines of inline `showDialog`.

/// How the operator wants to start: `scratch`, `image`, or null if dismissed.
Future<String?> askCreateMode(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Create character'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'scratch'),
          child: const Text('From scratch'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'image'),
          child: const Text('From image'),
        ),
      ],
    ),
  );
}

/// The name for a character built from an image, or null if dismissed.
///
/// Returns a trimmed, non-empty name or null -- the caller should never have to
/// re-check for whitespace it did not ask for.
Future<String?> askCharacterName(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _NameCharacterDialog(),
  );
}

Future<bool> confirmDeleteCharacter(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete character?'),
      content: Text('\u201c$name\u201d will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Stateful only because it owns a [TextEditingController].
///
/// The previous inline version built one inside a `showDialog` builder and
/// never disposed it, which leaks a controller and its listeners every time the
/// operator opens the prompt.
class _NameCharacterDialog extends StatefulWidget {
  const _NameCharacterDialog();

  @override
  State<_NameCharacterDialog> createState() => _NameCharacterDialogState();
}

class _NameCharacterDialogState extends State<_NameCharacterDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.pop(context, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name character'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Character name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}

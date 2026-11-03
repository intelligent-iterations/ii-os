import 'package:flutter/material.dart';

Future<bool> confirmCharacterDeletion(
  BuildContext context,
  String characterName,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete character?'),
        content: Text(
          '\u201c$characterName\u201d and its selected image references will be permanently deleted.',
        ),
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
    ) ==
    true;

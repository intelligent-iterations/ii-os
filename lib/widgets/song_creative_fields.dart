import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import 'prompt_enhance_bar.dart';

/// The two things a person writes for a song, each with its own rewrite.
///
/// They are deliberately not one field with one guide. The description is
/// direction ACE-Step may reinterpret freely; the lyrics are sung as written,
/// so their guide preserves the wording and only shapes it into singable
/// sections. Enhancing one under the other's rules is exactly the failure this
/// pairing exists to prevent.
class SongCreativeFields extends StatelessWidget {
  const SongCreativeFields({
    required this.description,
    required this.lyrics,
    required this.enabled,
    required this.instrumental,
    required this.onInstrumentalChanged,
    this.descriptionEnhance,
    this.lyricsEnhance,
    super.key,
  });

  final TextEditingController description;
  final TextEditingController lyrics;
  final bool enabled;
  final bool instrumental;
  final ValueChanged<bool>? onInstrumentalChanged;
  final PromptEnhanceBinding? descriptionEnhance;
  final PromptEnhanceBinding? lyricsEnhance;

  bool get _lyricsEnabled => enabled && !instrumental;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: description,
          enabled: enabled,
          minLines: 4,
          maxLines: 7,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Song description',
            hintText:
                'Genre, mood, instruments, vocal character, and structure',
            alignLabelWithHint: true,
          ),
        ),
        if (descriptionEnhance case final binding?)
          PromptEnhanceBar(
            controller: description,
            binding: binding,
            enabled: enabled,
          ),
        IiOsGap.vSm,
        TextField(
          controller: lyrics,
          enabled: _lyricsEnabled,
          minLines: 6,
          maxLines: 14,
          maxLength: 30000,
          decoration: InputDecoration(
            labelText: instrumental
                ? 'Lyrics disabled for instrumental'
                : 'Lyrics (optional)',
            hintText: '[Verse]\n...\n\n[Chorus]\n...',
            alignLabelWithHint: true,
          ),
        ),
        if (lyricsEnhance case final binding?)
          PromptEnhanceBar(
            controller: lyrics,
            binding: binding,
            enabled: _lyricsEnabled,
          ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Instrumental'),
          subtitle: const Text('Generate without sung vocals'),
          value: instrumental,
          onChanged: enabled ? onInstrumentalChanged : null,
        ),
      ],
    );
  }
}

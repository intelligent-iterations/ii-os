import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/song_render_profile.dart';

void main() {
  group('songRenderProfiles', () {
    test('ships provider-neutral default ids', () {
      expect(
        songRenderProfiles.map((profile) => profile.id),
        containsAll(const ['draft-120', 'quality-60']),
      );
      expect(
        parseSongRenderProfiles('').map((profile) => profile.id),
        containsAll(const ['draft-120', 'quality-60']),
      );
    });

    test('names the outcome, never the graph or the rack', () {
      const forbidden = [
        'ACE-Step',
        'XL Turbo',
        'XL SFT',
        'shift',
        'LM',
        'RTX',
        'VRAM',
        'steps',
      ];
      for (final profile in songRenderProfiles) {
        final copy = '${profile.label} ${profile.description}';
        for (final word in forbidden) {
          expect(
            copy.contains(word),
            isFalse,
            reason: '${profile.id} still says "$word"',
          );
        }
      }
    });

    test('each profile states the cap it actually enforces', () {
      // The sentence and the slider maximum have to agree, or the page tells
      // the person one thing and then refuses another.
      for (final profile in songRenderProfiles) {
        final minutes = profile.maxDurationMinutes;
        final phrase = minutes == 1 ? '1 minute' : '$minutes minutes';
        expect(
          profile.description,
          contains(phrase),
          reason: '${profile.id} caps at $minutes min and does not say so',
        );
      }
    });

    test('an unknown id falls back rather than failing', () {
      expect(songRenderProfileById('retired'), defaultSongRenderProfile);
      expect(songRenderProfileById(null), defaultSongRenderProfile);
      expect(songRenderProfileById('quality-60').label, 'Final quality');
    });

    test('parses an implementation-defined profile', () {
      final configured = parseSongRenderProfiles('''
        [{
          "id": "studio",
          "label": "Studio",
          "maxDurationSeconds": 90,
          "description": "Up to 1 minute of implementation-defined output."
        }]
      ''');

      expect(configured.single.id, 'studio');
      expect(configured.single.maxDurationSeconds, 90);
    });

    test('rejects malformed or duplicate implementation profiles', () {
      expect(() => parseSongRenderProfiles('[]'), throwsFormatException);
      expect(
        () => parseSongRenderProfiles('''
          [
            {"id":"same","label":"A","maxDurationSeconds":30,"description":"A"},
            {"id":"same","label":"B","maxDurationSeconds":30,"description":"B"}
          ]
        '''),
        throwsFormatException,
      );
    });
  });
}

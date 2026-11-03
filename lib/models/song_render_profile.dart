import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How a song is rendered: how long it may run, and how finished it comes out.
///
/// Profiles describe a user-visible tradeoff. Provider, checkpoint, host, and
/// GPU details belong to the implementation mapping, not this public model.
@immutable
final class SongRenderProfile {
  const SongRenderProfile({
    required this.id,
    required this.label,
    required this.maxDurationSeconds,
    required this.description,
  });

  /// The value the workflow branches on. Changing it changes which checkpoint
  /// runs, so it is not copy and must not be edited for readability.
  final String id;

  /// What this profile gets you, in two words.
  final String label;

  final double maxDurationSeconds;

  /// What choosing it means for the result, and what it costs.
  final String description;

  /// The cap, as the description states it.
  int get maxDurationMinutes => maxDurationSeconds ~/ 60;
}

const _defaultSongRenderProfilesJson = '''
[
  {
    "id": "draft-120",
    "label": "Full draft",
    "maxDurationSeconds": 120,
    "description": "Up to 2 minutes, and quicker. Best for hearing the whole idea before committing to it."
  },
  {
    "id": "quality-60",
    "label": "Final quality",
    "maxDurationSeconds": 60,
    "description": "Up to 1 minute, slower and cleaner. Best once the idea is settled and you want the recording."
  }
]
''';

final songRenderProfiles = parseSongRenderProfiles(
  const String.fromEnvironment(
    'II_OS_SONG_RENDER_PROFILES_JSON',
    defaultValue: _defaultSongRenderProfilesJson,
  ),
);

List<SongRenderProfile> parseSongRenderProfiles(String source) {
  final decoded = jsonDecode(
    source.trim().isEmpty ? _defaultSongRenderProfilesJson : source,
  );
  if (decoded is! List<Object?> || decoded.isEmpty || decoded.length > 8) {
    throw const FormatException(
      'Song render profiles must contain 1 to 8 entries.',
    );
  }
  final profiles = <SongRenderProfile>[];
  final ids = <String>{};
  for (final raw in decoded) {
    if (raw is! Map<String, Object?>) {
      throw const FormatException(
        'Each song render profile must be an object.',
      );
    }
    final id = raw['id'];
    final label = raw['label'];
    final duration = raw['maxDurationSeconds'];
    final description = raw['description'];
    if (id is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id) ||
        !ids.add(id) ||
        label is! String ||
        label.trim().isEmpty ||
        label.length > 80 ||
        duration is! num ||
        duration <= 0 ||
        duration > 600 ||
        description is! String ||
        description.trim().isEmpty ||
        description.length > 240) {
      throw const FormatException(
        'Song render profile configuration is invalid.',
      );
    }
    profiles.add(
      SongRenderProfile(
        id: id,
        label: label,
        maxDurationSeconds: duration.toDouble(),
        description: description,
      ),
    );
  }
  return List.unmodifiable(profiles);
}

final defaultSongRenderProfile = songRenderProfiles.first;

/// The profile [id] names, falling back to the default.
SongRenderProfile songRenderProfileById(String? id) {
  for (final profile in songRenderProfiles) {
    if (profile.id == id) return profile;
  }
  return defaultSongRenderProfile;
}

import 'package:google_cloud_firestore/google_cloud_firestore.dart';

/// How long a workspace keeps media that nothing is holding on to.
///
/// The window is per organization, configured on its artifact storage. It is
/// counted from the last time the media mattered rather than from when it was
/// made: something opened last week is not stale because it was generated two
/// months ago.
const defaultArtifactRetentionDays = 60;

/// The longest window an organization may configure. A window with no ceiling
/// is a bucket that only grows.
const maxArtifactRetentionDays = 60;

/// The shortest window, so a misconfiguration cannot delete media the moment
/// it is released.
const minArtifactRetentionDays = 1;

/// How stale a play record has to be before opening the media writes a new
/// one. Bounding it keeps playback from costing a write every time.
const artifactPlayRefreshInterval = Duration(days: 1);

/// The window this organization actually gets, whatever it has configured.
int artifactRetentionDays(int? configuredDays) =>
    (configuredDays ?? defaultArtifactRetentionDays).clamp(
      minArtifactRetentionDays,
      maxArtifactRetentionDays,
    );

/// When media that nothing holds should leave the bucket, counted from now.
///
/// Nothing here decides whether media is held: held media carries no expiry at
/// all, and only gets one when the last thing referring to it lets go.
Timestamp artifactExpiry({required int retentionDays, DateTime? now}) =>
    Timestamp.fromDate(
      (now ?? DateTime.now()).toUtc().add(
        Duration(
          days: retentionDays.clamp(
            minArtifactRetentionDays,
            maxArtifactRetentionDays,
          ),
        ),
      ),
    );

/// The expiry a play should leave behind, or null to change nothing.
///
/// This is the whole of "deleted after sixty days, unless it has been played":
/// opening media that is on its way out starts its window again, so the thing
/// that gets deleted is the thing nobody has looked at, not the thing that
/// happens to be old. Media something still holds has no expiry to push, and
/// a play that lands within [artifactPlayRefreshInterval] of the last one
/// writes nothing.
Timestamp? refreshedArtifactExpiry({
  required Map<String, Object?>? data,
  required int retentionDays,
  DateTime? now,
}) {
  if (data == null || data['expiresAt'] == null) return null;
  if (!shouldRecordArtifactPlay(
    lastPlayedAt: artifactLastPlayedAt(data),
    now: now,
  )) {
    return null;
  }
  return artifactExpiry(retentionDays: retentionDays, now: now);
}

/// Whether opening media now is worth recording, given when it was last
/// opened. Playing the same clip ten times in a minute is one write, not ten.
bool shouldRecordArtifactPlay({DateTime? lastPlayedAt, DateTime? now}) {
  if (lastPlayedAt == null) return true;
  final at = (now ?? DateTime.now()).toUtc();
  return at.difference(lastPlayedAt.toUtc()).abs() >=
      artifactPlayRefreshInterval;
}

/// The play record stored on a job run or source asset, if it has one.
DateTime? artifactLastPlayedAt(Map<String, Object?>? data) {
  final value = data?['lastPlayedAt'];
  return switch (value) {
    Timestamp() => value.toDate().toUtc(),
    String() => DateTime.tryParse(value)?.toUtc(),
    _ => null,
  };
}

import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'prompt_enhancement_key_codec.dart';

/// Holds the DeepSeek key a workspace pasted into ii-os.
///
/// Kept in its own collection rather than on the workspace document, because
/// the workspace document is what the API returns. A secret that lives beside
/// the fields a route serialises is one forgotten `toJson` away from being
/// handed to a client, and the collection boundary makes that mistake
/// impossible rather than unlikely.
final class PromptEnhancementKeyStore {
  PromptEnhancementKeyStore({
    required this.firestore,
    required this.codec,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  final Firestore firestore;
  final PromptEnhancementKeyCodec codec;
  final DateTime Function() _clock;

  CollectionReference<Map<String, Object?>> get _keys =>
      firestore.collection('workspacePromptEnhancementKeys');

  /// Stores [apiKey] for [workspaceId] and returns its last four characters.
  Future<String> write({
    required String workspaceId,
    required String apiKey,
    required String updatedBy,
  }) async {
    final normalized = apiKey.trim();
    if (normalized.length < 8 || normalized.length > 4096) {
      throw const ApiError(
        400,
        'invalid_deepseek_api_key',
        'Paste the DeepSeek API key exactly as DeepSeek issued it.',
      );
    }
    if (!codec.isConfigured) {
      throw const ApiError(
        503,
        'prompt_enhancement_key_storage_unavailable',
        'ii-os cannot store an API key right now. Try again shortly.',
      );
    }
    final sealed = await codec.seal(
      workspaceId: workspaceId,
      apiKey: normalized,
    );
    await _keys.doc(workspaceId).set({
      ...sealed,
      'workspaceId': workspaceId,
      'updatedBy': updatedBy,
      'updatedAt': Timestamp.fromDate(_clock()),
    });
    return lastFour(normalized);
  }

  /// Removes the stored key. Safe to call when there is none.
  Future<void> clear(String workspaceId) async {
    await _keys.doc(workspaceId).delete();
  }

  /// Recovers the stored key, or null when there is none to recover.
  ///
  /// A version-1 record is re-sealed transactionally with the dedicated key.
  /// Reading and migration share one transaction so a concurrent key update
  /// cannot be overwritten by stale ciphertext.
  Future<String?> read(String workspaceId) async {
    if (!codec.isConfigured) return null;
    final ref = _keys.doc(workspaceId);
    return firestore.runTransaction<String?>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data == null) return null;
      final apiKey = await codec.open(workspaceId: workspaceId, sealed: data);
      if (apiKey == null || !codec.needsMigration(data)) return apiKey;
      transaction.update(ref, {
        ...await codec.seal(workspaceId: workspaceId, apiKey: apiKey),
        'migratedAt': Timestamp.fromDate(_clock()),
      });
      return apiKey;
    });
  }
}

DateTime _utcNow() => DateTime.now().toUtc();

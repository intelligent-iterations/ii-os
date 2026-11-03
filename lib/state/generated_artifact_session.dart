import 'package:flutter/foundation.dart';

import '../services/verified_artifact_media.dart';

typedef GeneratedArtifactLoader = Future<VerifiedArtifactMedia> Function();
typedef GhostArtifactConsumer = Future<void> Function();

/// Owns the browser-memory lifetime of one generated artifact.
final class GeneratedArtifactSession extends ChangeNotifier {
  GeneratedArtifactSession({
    required this.ghostMode,
    required GeneratedArtifactLoader load,
    required GhostArtifactConsumer consume,
  }) : _loadMedia = load,
       _consumeGhost = consume {
    media = _load();
  }

  final bool ghostMode;
  final GeneratedArtifactLoader _loadMedia;
  final GhostArtifactConsumer _consumeGhost;

  late Future<VerifiedArtifactMedia> media;
  bool _consumed = false;
  bool cleaning = false;
  bool _disposed = false;
  Object? cleanupError;

  Future<VerifiedArtifactMedia> _load() async {
    final loaded = await _loadMedia();
    if (ghostMode && !_consumed) {
      try {
        await _consume();
      } on Object {
        // The verified bytes remain available to the mounted output widget.
      }
    }
    return loaded;
  }

  Future<void> _consume() async {
    if (_consumed || cleaning) return;
    cleaning = true;
    _notify();
    try {
      await _consumeGhost();
      _consumed = true;
      cleanupError = null;
    } on Object catch (error) {
      cleanupError = error;
      rethrow;
    } finally {
      cleaning = false;
      _notify();
    }
  }

  void reload() {
    _consumed = false;
    cleanupError = null;
    media = _load();
    _notify();
  }

  Future<void> retryCleanup() async {
    try {
      await _consume();
    } on Object {
      // Keep the recovery surface visible for another attempt.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

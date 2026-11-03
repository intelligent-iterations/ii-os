import 'dart:async';
import 'dart:convert';

import '../models/character.dart';
import '../models/character_generation_state.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import 'polling_cost_policy.dart';

final class CharacterGenerationWatcher {
  CharacterGenerationWatcher({
    required this.controller,
    required this.workspaceId,
    required this.loadImages,
    required this.handleCompletedImage,
    required this.refreshCharacter,
    required this.onJobChanged,
  });

  final AppController controller;
  final String workspaceId;
  final Future<List<CharacterImageModel>> Function() loadImages;
  final Future<bool> Function(CharacterImageModel image, JsonMap job)
  handleCompletedImage;
  final Future<void> Function() refreshCharacter;
  final void Function(JsonMap job) onJobChanged;

  Timer? _timer;
  String? _jobId;
  int _completedWithoutImagePolls = 0;
  bool _refreshing = false;
  bool _disposed = false;
  String? _lastJobFingerprint;

  void watch(String jobId) {
    if (_disposed || jobId.isEmpty) return;
    if (_jobId != jobId) {
      _jobId = jobId;
      _completedWithoutImagePolls = 0;
      _lastJobFingerprint = null;
    }
    _timer?.cancel();
    _timer = Timer.periodic(
      IiOsPollingCostPolicy.activeOperation,
      (_) => unawaited(_refresh(jobId)),
    );
    unawaited(_refresh(jobId));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh(String jobId) async {
    if (_disposed || _refreshing || _jobId != jobId) return;
    _refreshing = true;
    try {
      final response = await controller.api.get(
        'v1/workspaces/$workspaceId/jobs/${Uri.encodeComponent(jobId)}',
      );
      final job = asJsonMap(response['job']);
      if (_disposed || _jobId != jobId) return;
      final status = job['status'] as String? ?? '';
      final completed = status == 'completed';
      if (!completed) _notifyJobChanged(job);
      if (shouldLoadCharacterImagesForGenerationStatus(status)) {
        final images = await loadImages();
        if (_disposed || _jobId != jobId) return;
        final completedImage = characterImageForJob(images, jobId);
        if (completedImage == null) {
          _completedWithoutImagePolls++;
          onJobChanged(
            _completedWithoutImagePolls >= 5
                ? {
                    ...job,
                    'status': 'failed',
                    'errorCode': 'generated_artifact_missing',
                  }
                : job,
          );
          if (_completedWithoutImagePolls >= 5) _stop();
          return;
        }
        if (!completedImage.selected &&
            !await handleCompletedImage(completedImage, job)) {
          return;
        }
        await refreshCharacter();
        if (_disposed || _jobId != jobId) return;
        onJobChanged(job);
        _stop();
      } else if (_terminalStatuses.contains(status)) {
        await refreshCharacter();
        _stop();
      }
    } on Object {
      // A transient job or signed-history failure must not stop the listener.
    } finally {
      _refreshing = false;
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _jobId = null;
    _lastJobFingerprint = null;
  }

  void _notifyJobChanged(JsonMap job) {
    final fingerprint = jsonEncode(job);
    if (_lastJobFingerprint == fingerprint) return;
    _lastJobFingerprint = fingerprint;
    onJobChanged(job);
  }
}

const _terminalStatuses = {'completed', 'failed', 'cancelled'};

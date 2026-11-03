part of 'composition_compiler.dart';

/// Stable reasons that a timeline cannot use a declared render target.
enum EditorRenderIssueCode {
  invalidProject,
  unsupportedSourceUse,
  conflictingSourceIdentity,
  incompatibleSourceUse,
  unsupportedOutputProfile,
  videoBitrateExceeded,
  audioBitrateExceeded,
  emittedLayerLimitExceeded,
  inputLimitExceeded,
  sourceByteLengthExceeded,
  declaredInputBytesExceeded,
  preparedInputBytesExceeded,
  estimatedOutputBytesExceeded,
  captionPixelLimitExceeded,
  captionTotalPixelLimitExceeded,
}

/// One target-specific structural blocker found without preparing media.
@immutable
final class EditorRenderIssue {
  const EditorRenderIssue({
    required this.code,
    required this.message,
    this.laneId,
    this.clipId,
    this.sourceId,
    this.actual,
    this.maximum,
  });

  final EditorRenderIssueCode code;
  final String message;
  final String? laneId;
  final String? clipId;
  final String? sourceId;
  final int? actual;
  final int? maximum;
}

/// Resource accounting for the compiler's current occurrence-layer graph.
@immutable
final class EditorRenderFootprint {
  const EditorRenderFootprint({
    required this.emittedLayerCount,
    required this.mediaInputCount,
    required this.captionInputCount,
    required this.declaredMediaBytes,
    required this.reservedCaptionBytes,
    required this.estimatedOutputBytes,
    required this.captionPixelCount,
    required this.peakVisualConcurrency,
    required this.peakAudioConcurrency,
  });

  final int emittedLayerCount;
  final int mediaInputCount;
  final int captionInputCount;
  final int declaredMediaBytes;
  final int reservedCaptionBytes;
  final int estimatedOutputBytes;
  final int captionPixelCount;
  final int peakVisualConcurrency;
  final int peakAudioConcurrency;

  int get totalInputCount => mediaInputCount + captionInputCount;
  int get maximumPreparedInputBytes =>
      declaredMediaBytes + reservedCaptionBytes;

  @override
  bool operator ==(Object other) =>
      other is EditorRenderFootprint &&
      emittedLayerCount == other.emittedLayerCount &&
      mediaInputCount == other.mediaInputCount &&
      captionInputCount == other.captionInputCount &&
      declaredMediaBytes == other.declaredMediaBytes &&
      reservedCaptionBytes == other.reservedCaptionBytes &&
      estimatedOutputBytes == other.estimatedOutputBytes &&
      captionPixelCount == other.captionPixelCount &&
      peakVisualConcurrency == other.peakVisualConcurrency &&
      peakAudioConcurrency == other.peakAudioConcurrency;

  @override
  int get hashCode => Object.hash(
    emittedLayerCount,
    mediaInputCount,
    captionInputCount,
    declaredMediaBytes,
    reservedCaptionBytes,
    estimatedOutputBytes,
    captionPixelCount,
    peakVisualConcurrency,
    peakAudioConcurrency,
  );
}

/// Pure structural result; it does not promise media availability or execution.
@immutable
final class EditorRenderFeasibility {
  EditorRenderFeasibility._({
    required this.footprint,
    required Iterable<EditorRenderIssue> issues,
  }) : issues = List<EditorRenderIssue>.unmodifiable(issues);

  final EditorRenderFootprint? footprint;
  final List<EditorRenderIssue> issues;

  bool get isStructurallyFeasible => issues.isEmpty;
  bool get requiresPreparation => (footprint?.totalInputCount ?? 0) > 0;

  void throwIfInfeasible() {
    if (issues case [final first, ...]) {
      throw EditorValidationException(first.message);
    }
  }
}

/// Analyzes the package-owned target without opening sources or rasterizing text.
EditorRenderFeasibility preflightEditorRender(
  EditorProject project, {
  EditorLimits limits = const EditorLimits(),
  MediaLimits mediaLimits = const MediaLimits(),
}) {
  mediaLimits.validateSelf();
  return _analyzeEditorRender(
    project,
    limits: limits,
    mediaLimits: mediaLimits,
    maxSourceBytes: mediaLimits.maxSourceBytes,
    maxDeclaredMediaBytes: mediaLimits.declaredMediaByteLimit,
    maxInputBytes: mediaLimits.maxInputBytes,
    maxEstimatedOutputBytes: mediaLimits.estimatedOutputByteLimit,
  ).report;
}

/// Conservative encoded byte estimate from the declared output bitrates.
///
/// The split calculation keeps every intermediate below JavaScript's exact
/// integer ceiling for all validated editor durations and bitrates.
int estimateEditorOutputBytes(EditorProject project) {
  final bitsPerSecond =
      project.output.videoBitrate + project.output.audioBitrate;
  if (bitsPerSecond <= 0) return 0;
  final wholeSeconds =
      project.duration.microseconds ~/ Duration.microsecondsPerSecond;
  final remainingMicroseconds =
      project.duration.microseconds % Duration.microsecondsPerSecond;
  final wholeSecondBits = bitsPerSecond * wholeSeconds;
  final remainingBitMicroseconds =
      (wholeSecondBits % 8) * Duration.microsecondsPerSecond +
      bitsPerSecond * remainingMicroseconds;
  return wholeSecondBits ~/ 8 +
      (remainingBitMicroseconds + 8 * Duration.microsecondsPerSecond - 1) ~/
          (8 * Duration.microsecondsPerSecond);
}

final class _EditorPlannedLayer {
  const _EditorPlannedLayer({
    required this.laneId,
    required this.clip,
    this.captionRequest,
    this.captionIndex,
    this.captionSourceId,
  });

  final String laneId;
  final EditorClip clip;
  final EditorCaptionRasterRequest? captionRequest;
  final int? captionIndex;
  final String? captionSourceId;
}

final class _EditorRenderAnalysis {
  const _EditorRenderAnalysis({required this.report, required this.layers});

  final EditorRenderFeasibility report;
  final List<_EditorPlannedLayer> layers;
}

_EditorRenderAnalysis _analyzeEditorRender(
  EditorProject project, {
  required EditorLimits limits,
  required MediaLimits mediaLimits,
  required int maxSourceBytes,
  required int maxDeclaredMediaBytes,
  required int maxInputBytes,
  required int maxEstimatedOutputBytes,
}) {
  limits.validateSelf();
  try {
    validateEditorProject(project, limits: limits);
  } on EditorValidationException catch (error) {
    return _EditorRenderAnalysis(
      report: EditorRenderFeasibility._(
        footprint: null,
        issues: [
          EditorRenderIssue(
            code: EditorRenderIssueCode.invalidProject,
            message: error.message,
          ),
        ],
      ),
      layers: const [],
    );
  }

  final layers = <_EditorPlannedLayer>[];
  final issues = <EditorRenderIssue>[];
  final mediaSources = Set<MediaSource>.identity();
  final sourceIds = <String, MediaSource>{};
  final sourceFormats = Map<MediaSource, Set<_EditorInputFormat>>.identity();
  final sourceOrder = <MediaSource>[];
  var captionInputCount = 0;
  var captionPixelCount = 0;
  var declaredMediaBytes = 0;

  void addMedia(
    EditorLane lane,
    EditorClip clip,
    MediaSource source,
    _EditorSourceRole role,
  ) {
    layers.add(_EditorPlannedLayer(laneId: lane.id, clip: clip));
    final format = _inputFormatForSource(source, role);
    if (format == null) {
      issues.add(
        EditorRenderIssue(
          code: EditorRenderIssueCode.unsupportedSourceUse,
          message:
              'Source ${source.id} cannot be used as ${role.name} from '
              '.${source.fileExtension}.',
          laneId: lane.id,
          clipId: clip.id,
          sourceId: source.id,
        ),
      );
    } else {
      sourceFormats
          .putIfAbsent(source, () => <_EditorInputFormat>{})
          .add(format);
    }
    if (!mediaSources.add(source)) return;
    sourceOrder.add(source);

    final prior = sourceIds[source.id];
    if (prior != null && !identical(prior, source)) {
      issues.add(
        EditorRenderIssue(
          code: EditorRenderIssueCode.conflictingSourceIdentity,
          message: 'Source ID ${source.id} refers to multiple byte streams.',
          laneId: lane.id,
          clipId: clip.id,
          sourceId: source.id,
        ),
      );
    } else {
      sourceIds[source.id] = source;
    }
    declaredMediaBytes += source.byteLength;
    if (source.byteLength > maxSourceBytes) {
      issues.add(
        EditorRenderIssue(
          code: EditorRenderIssueCode.sourceByteLengthExceeded,
          message: 'Source ${source.id} exceeds the per-source input limit.',
          laneId: lane.id,
          clipId: clip.id,
          sourceId: source.id,
          actual: source.byteLength,
          maximum: maxSourceBytes,
        ),
      );
    }
  }

  for (final lane in project.lanes) {
    if (lane.hidden) continue;
    for (final clip in lane.clips) {
      switch (clip) {
        case final EditorVideoClip video:
          addMedia(lane, video, video.source, _EditorSourceRole.video);
        case final EditorAudioClip audio:
          if (lane.muted) continue;
          addMedia(lane, audio, audio.source, _EditorSourceRole.audio);
        case final EditorCaptionClip caption:
          final request = EditorCaptionRasterRequest(
            clip: caption,
            canvasWidth: project.width,
            canvasHeight: project.height,
            limits: limits,
          );
          final pixels = request.pixelWidth * request.pixelHeight;
          layers.add(
            _EditorPlannedLayer(
              laneId: lane.id,
              clip: caption,
              captionRequest: request,
              captionIndex: captionInputCount,
            ),
          );
          captionInputCount++;
          captionPixelCount += pixels;
          if (pixels > limits.maxCaptionPixels) {
            issues.add(
              EditorRenderIssue(
                code: EditorRenderIssueCode.captionPixelLimitExceeded,
                message: 'Caption ${caption.id} exceeds its pixel limit.',
                laneId: lane.id,
                clipId: caption.id,
                actual: pixels,
                maximum: limits.maxCaptionPixels,
              ),
            );
          }
      }
    }
  }

  for (final source in sourceOrder) {
    final formats = sourceFormats[source];
    if (formats == null || formats.length <= 1) continue;
    issues.add(
      EditorRenderIssue(
        code: EditorRenderIssueCode.incompatibleSourceUse,
        message: 'Source ${source.id} is used with incompatible layer types.',
        sourceId: source.id,
      ),
    );
  }

  final reservedSourceIds = sourceIds.keys.toSet();
  final finalizedLayers = [
    for (final planned in layers)
      if (planned.clip case final EditorCaptionClip caption)
        _EditorPlannedLayer(
          laneId: planned.laneId,
          clip: caption,
          captionRequest: planned.captionRequest,
          captionIndex: planned.captionIndex,
          captionSourceId: _reserveCaptionSourceId(
            planned.captionIndex!,
            caption.id,
            reservedSourceIds,
          ),
        )
      else
        planned,
  ];

  final transitionHolds = <String, MediaTime>{};
  _resolveTransitions(
    project,
    <String, MediaVisualTransition>{},
    transitionHolds,
  );

  final footprint = EditorRenderFootprint(
    emittedLayerCount: finalizedLayers.length,
    mediaInputCount: mediaSources.length,
    captionInputCount: captionInputCount,
    declaredMediaBytes: declaredMediaBytes,
    reservedCaptionBytes: math.min(
      captionInputCount * limits.maxCaptionRasterBytes,
      limits.maxCaptionTotalRasterBytes,
    ),
    estimatedOutputBytes: estimateEditorOutputBytes(project),
    captionPixelCount: captionPixelCount,
    peakVisualConcurrency: _peakConcurrency(
      finalizedLayers,
      audio: false,
      transitionHolds: transitionHolds,
    ),
    peakAudioConcurrency: _peakConcurrency(
      finalizedLayers,
      audio: true,
      transitionHolds: transitionHolds,
    ),
  );
  _addAggregateIssues(
    issues,
    project,
    footprint,
    limits,
    mediaLimits,
    maxDeclaredMediaBytes,
    maxInputBytes,
    maxEstimatedOutputBytes,
  );
  return _EditorRenderAnalysis(
    report: EditorRenderFeasibility._(footprint: footprint, issues: issues),
    layers: List<_EditorPlannedLayer>.unmodifiable(finalizedLayers),
  );
}

String _reserveCaptionSourceId(int index, String clipId, Set<String> reserved) {
  final prefix = 'caption-${index.toString().padLeft(4, '0')}-';
  for (var attempt = 0; ; attempt++) {
    final suffix = attempt == 0 ? '' : '-$attempt';
    final available = 128 - prefix.length - suffix.length;
    final safeClip = clipId.substring(0, math.min(available, clipId.length));
    final candidate = '$prefix$safeClip$suffix';
    if (reserved.add(candidate)) return candidate;
  }
}

void _addAggregateIssues(
  List<EditorRenderIssue> issues,
  EditorProject project,
  EditorRenderFootprint footprint,
  EditorLimits limits,
  MediaLimits mediaLimits,
  int maxDeclaredMediaBytes,
  int maxInputBytes,
  int maxEstimatedOutputBytes,
) {
  void addLimit(
    EditorRenderIssueCode code,
    String message,
    int actual,
    int maximum,
  ) {
    if (actual > maximum) {
      issues.add(
        EditorRenderIssue(
          code: code,
          message: message,
          actual: actual,
          maximum: maximum,
        ),
      );
    }
  }

  addLimit(
    EditorRenderIssueCode.emittedLayerLimitExceeded,
    'Project exceeds the render target layer limit.',
    footprint.emittedLayerCount,
    mediaLimits.maxLayerCount,
  );
  addLimit(
    EditorRenderIssueCode.inputLimitExceeded,
    'Project exceeds the render target input limit.',
    footprint.totalInputCount,
    mediaLimits.maxInputCount,
  );
  addLimit(
    EditorRenderIssueCode.declaredInputBytesExceeded,
    'Declared media bytes exceed the declared-media allowance.',
    footprint.declaredMediaBytes,
    maxDeclaredMediaBytes,
  );
  if (footprint.reservedCaptionBytes > 0) {
    addLimit(
      EditorRenderIssueCode.preparedInputBytesExceeded,
      'Declared media and reserved caption bytes exceed the aggregate input '
      'limit.',
      footprint.maximumPreparedInputBytes,
      maxInputBytes,
    );
  }
  addLimit(
    EditorRenderIssueCode.estimatedOutputBytesExceeded,
    'Estimated output bytes exceed the render target planning limit.',
    footprint.estimatedOutputBytes,
    maxEstimatedOutputBytes,
  );
  addLimit(
    EditorRenderIssueCode.captionTotalPixelLimitExceeded,
    'Caption raster pixels exceed the project aggregate limit.',
    footprint.captionPixelCount,
    limits.maxCaptionTotalPixels,
  );
  addLimit(
    EditorRenderIssueCode.videoBitrateExceeded,
    'Output video bitrate exceeds the render target limit.',
    project.output.videoBitrate,
    mediaLimits.maxVideoBitrate,
  );
  addLimit(
    EditorRenderIssueCode.audioBitrateExceeded,
    'Output audio bitrate exceeds the render target limit.',
    project.output.audioBitrate,
    mediaLimits.maxAudioBitrate,
  );
  if (project.output.videoBitrate <= 0 || project.output.audioBitrate <= 0) {
    issues.add(
      const EditorRenderIssue(
        code: EditorRenderIssueCode.unsupportedOutputProfile,
        message: 'Output bitrates must be positive.',
      ),
    );
  }
  final webm = project.output.container == MediaContainer.webm;
  final incompatible = webm
      ? project.output.videoCodec == MediaVideoCodec.h264 ||
            project.output.videoCodec == MediaVideoCodec.mpeg4 ||
            project.output.audioCodec == MediaAudioCodec.aac
      : project.output.videoCodec == MediaVideoCodec.vp9 ||
            project.output.audioCodec == MediaAudioCodec.opus;
  if (incompatible) {
    issues.add(
      const EditorRenderIssue(
        code: EditorRenderIssueCode.unsupportedOutputProfile,
        message: 'Output codecs are incompatible with the selected container.',
      ),
    );
  }
}

int _peakConcurrency(
  List<_EditorPlannedLayer> layers, {
  required bool audio,
  required Map<String, MediaTime> transitionHolds,
}) {
  final events = <({int time, int delta})>[];
  for (final planned in layers) {
    if ((planned.clip is EditorAudioClip) != audio) continue;
    events.add((time: planned.clip.timelineStart.microseconds, delta: 1));
    final hold = audio
        ? MediaTime.zero
        : transitionHolds[planned.clip.id] ?? MediaTime.zero;
    events.add((
      time: planned.clip.timelineEnd.microseconds + hold.microseconds,
      delta: -1,
    ));
  }
  events.sort((left, right) {
    final time = left.time.compareTo(right.time);
    return time != 0 ? time : left.delta.compareTo(right.delta);
  });
  var active = 0;
  var peak = 0;
  for (final event in events) {
    active += event.delta;
    peak = math.max(peak, active);
  }
  return peak;
}

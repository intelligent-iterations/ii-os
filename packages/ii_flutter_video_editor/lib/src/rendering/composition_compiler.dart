import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/rendering/cancellation.dart';
import 'package:ii_flutter_video_editor/src/rendering/caption_rasterizer.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';
import 'package:ii_flutter_video_editor/src/transition_edits.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';
import 'package:meta/meta.dart';

part 'composition_arguments.dart';
part 'render_target.dart';
part 'render_feasibility.dart';
part 'caption_png_normalizer.dart';
part 'png_validator.dart';

@immutable
final class EditorRenderPlan {
  const EditorRenderPlan({
    required this.composition,
    required this.job,
    required this.outputName,
    required this.mediaType,
  });

  final MediaComposition composition;
  final FfmpegJob job;
  final String outputName;
  final String mediaType;

  List<MediaLayer> get layers => composition.layers;
}

final class EditorCompositionCompiler {
  // Kept as an explicit parameter to preserve the established `limits:` API.
  // ignore: prefer_initializing_formals
  const EditorCompositionCompiler({
    this.captionRasterizer = const FlutterCaptionRasterizer(),
    EditorLimits limits = const EditorLimits(),
  }) : _legacyLimits = limits,
       _renderTarget = null;

  const EditorCompositionCompiler.forTarget(
    EditorRenderTarget this._renderTarget, {
    this.captionRasterizer = const FlutterCaptionRasterizer(),
  }) : _legacyLimits = const EditorLimits();

  final EditorCaptionRasterizer captionRasterizer;
  final EditorLimits _legacyLimits;
  final EditorRenderTarget? _renderTarget;

  EditorRenderTarget get target =>
      _renderTarget ?? EditorRenderTarget(editorLimits: _legacyLimits);

  EditorLimits get limits => target.editorLimits;

  /// Checks the current compilation target without opening or preparing media.
  EditorRenderFeasibility preflight(
    EditorProject project, {
    MediaLimits? mediaLimits,
    FfmpegSafetyPolicy? safety,
  }) {
    final effectiveTarget = _effectiveTarget(mediaLimits, safety);
    return _analyzeEditorRender(
      project,
      limits: effectiveTarget.editorLimits,
      mediaLimits: effectiveTarget.mediaLimits,
      maxSourceBytes: effectiveTarget.maxSourceBytes,
      maxDeclaredMediaBytes: effectiveTarget.maxDeclaredMediaBytes,
      maxInputBytes: effectiveTarget.maxInputBytes,
      maxEstimatedOutputBytes: effectiveTarget.maxEstimatedOutputBytes,
    ).report;
  }

  Future<EditorRenderPlan> compile(
    EditorProject project, {
    MediaLimits? mediaLimits,
    FfmpegSafetyPolicy? safety,
    EditorRenderCancellationToken? cancellation,
  }) async {
    final effectiveTarget = _effectiveTarget(mediaLimits, safety);
    final maxSourceBytes = effectiveTarget.maxSourceBytes;
    final maxInputBytes = effectiveTarget.maxInputBytes;
    final analysis = _analyzeEditorRender(
      project,
      limits: effectiveTarget.editorLimits,
      mediaLimits: effectiveTarget.mediaLimits,
      maxSourceBytes: maxSourceBytes,
      maxDeclaredMediaBytes: effectiveTarget.maxDeclaredMediaBytes,
      maxInputBytes: maxInputBytes,
      maxEstimatedOutputBytes: effectiveTarget.maxEstimatedOutputBytes,
    );
    analysis.report.throwIfInfeasible();
    final preparation = cancellation ?? EditorRenderCancellationToken();
    preparation.throwIfCancelled();
    final composition = await _compileComposition(
      project,
      analysis,
      maxSourceBytes,
      maxInputBytes,
      preparation,
    );
    preparation.throwIfCancelled();
    return _compileJob(composition, effectiveTarget, preparation);
  }

  EditorRenderTarget _effectiveTarget(
    MediaLimits? mediaLimits,
    FfmpegSafetyPolicy? safety,
  ) {
    if (_renderTarget != null && (mediaLimits != null || safety != null)) {
      throw ArgumentError(
        'A target-configured compiler does not accept per-call limit '
        'overrides.',
      );
    }
    return target.withOverrides(mediaLimits: mediaLimits, safety: safety)
      ..validate();
  }

  Future<MediaComposition> _compileComposition(
    EditorProject project,
    _EditorRenderAnalysis analysis,
    int maxSourceBytes,
    int maxInputBytes,
    EditorRenderCancellationToken cancellation,
  ) async {
    final layers = <MediaLayer>[];
    var captionBytes = 0;
    var totalInputBytes = analysis.report.footprint!.declaredMediaBytes;
    final arrivals = <String, MediaVisualTransition>{};
    final holds = <String, MediaTime>{};
    _resolveTransitions(project, arrivals, holds);
    for (final planned in analysis.layers) {
      cancellation.throwIfCancelled();
      switch (planned.clip) {
        case final EditorVideoClip clip:
          layers.add(
            MediaVideoLayer(
              id: clip.id,
              source: clip.source,
              sourceRange: clip.sourceRange,
              timelineStart: clip.timelineStart,
              destination: clip.destination,
              fit: clip.fit,
              opacity: clip.opacity,
              transitionIn: arrivals[clip.id],
              holdAfter: holds[clip.id] ?? MediaTime.zero,
            ),
          );
        case final EditorAudioClip clip:
          layers.add(
            MediaAudioLayer(
              id: clip.id,
              source: clip.source,
              sourceRange: clip.sourceRange,
              timelineStart: clip.timelineStart,
              volume: clip.volume,
            ),
          );
        case final EditorCaptionClip clip:
          final request = planned.captionRequest!;
          final rasterBytes = await _rasterize(request, cancellation);
          if (rasterBytes.length > limits.maxCaptionRasterBytes ||
              !_isExpectedCaptionPng(
                rasterBytes,
                expectedWidth: request.pixelWidth,
                expectedHeight: request.pixelHeight,
              )) {
            throw EditorValidationException(
              'Caption ${clip.id} raster output is not a bounded PNG.',
            );
          }
          final bytes = await _normalizeCaptionPng(
            rasterBytes,
            request,
            cancellation,
          );
          if (bytes.length > maxSourceBytes) {
            throw EditorValidationException(
              'Caption ${clip.id} exceeds the per-source input limit.',
            );
          }
          captionBytes += bytes.length;
          totalInputBytes += bytes.length;
          if (captionBytes > limits.maxCaptionTotalRasterBytes ||
              totalInputBytes > maxInputBytes) {
            throw const EditorValidationException(
              'Caption or media input bytes exceed the aggregate limit.',
            );
          }
          final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
          final source = MediaSource(
            id: planned.captionSourceId!,
            byteLength: snapshot.length,
            fileExtension: 'png',
            openRead: () => Stream<List<int>>.value(snapshot),
          );
          layers.add(
            MediaImageLayer(
              id: clip.id,
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: clip.duration,
              ),
              timelineStart: clip.timelineStart,
              destination: clip.destination,
              fit: MediaFit.fill,
            ),
          );
      }
    }
    return MediaComposition(
      width: project.width,
      height: project.height,
      framesPerSecond: project.framesPerSecond,
      duration: project.duration,
      layers: layers,
      output: project.output,
      backgroundColor: project.backgroundColor,
    );
  }

  Future<EditorRenderPlan> _compileJob(
    MediaComposition composition,
    EditorRenderTarget target,
    EditorRenderCancellationToken cancellation,
  ) async {
    final mediaLimits = target.mediaLimits;
    final safety = target.safety;
    _validateOutput(composition.output, mediaLimits);
    final sourceLayers = Map<MediaSource, List<MediaLayer>>.identity();
    final sourceIds = <String, MediaSource>{};
    for (final layer in composition.layers) {
      final prior = sourceIds[layer.source.id];
      if (prior != null && !identical(prior, layer.source)) {
        throw EditorValidationException(
          'Source ID ${layer.source.id} refers to multiple byte streams.',
        );
      }
      sourceIds[layer.source.id] = layer.source;
      sourceLayers.putIfAbsent(layer.source, () => <MediaLayer>[]).add(layer);
    }
    if (sourceLayers.length > mediaLimits.maxInputCount) {
      throw const EditorValidationException(
        'Project exceeds the Universal FFmpeg input limit.',
      );
    }

    final inputs = <FfmpegInput>[];
    final names = <MediaSource, String>{};
    final formats = <MediaSource, String>{};
    var totalBytes = 0;
    for (final entry in sourceLayers.entries) {
      cancellation.throwIfCancelled();
      final source = entry.key;
      if (source.byteLength > mediaLimits.maxSourceBytes) {
        throw EditorValidationException(
          'Source ${source.id} exceeds the per-source input limit.',
        );
      }
      totalBytes += source.byteLength;
      if (totalBytes > mediaLimits.maxInputBytes ||
          totalBytes > safety.maxTotalInputBytes) {
        throw const EditorValidationException(
          'Media source bytes exceed the aggregate input limit.',
        );
      }
      final index = inputs.length;
      final name = 'input-$index.${source.fileExtension}';
      final inputFormats = entry.value.map(_inputFormatFor).toSet();
      if (inputFormats.length != 1) {
        throw EditorValidationException(
          'Source ${source.id} is used with incompatible layer types.',
        );
      }
      final bytes = await _readSource(source, mediaLimits, cancellation);
      inputs.add(FfmpegBytesInput(name, bytes));
      names[source] = name;
      formats[source] = inputFormats.single;
    }

    final arguments = <String>[];
    for (final entry in sourceLayers.entries) {
      final format = formats[entry.key]!;
      arguments.addAll(['-f', format]);
      if (format == 'image2') {
        arguments.addAll(const ['-loop', '1']);
      }
      arguments.addAll(['-i', names[entry.key]!]);
    }
    arguments.addAll(_renderArguments(composition, sourceLayers.keys.toList()));
    final outputName = 'output.${_extension(composition.output.container)}';
    arguments.addAll(['-f', _muxer(composition.output.container), outputName]);
    final outputLimit = target.maxOutputBytes;
    final job = FfmpegJob(
      id: composition.layers.isEmpty ? 'editor-empty' : 'editor-render',
      arguments: arguments,
      inputs: inputs,
      outputs: [FfmpegOutput(outputName, maxBytes: outputLimit)],
      expectedDuration: Duration(
        microseconds: composition.duration.microseconds,
      ),
      timeout: safety.defaultTimeout,
    );
    safety.validate(job);
    return EditorRenderPlan(
      composition: composition,
      job: job,
      outputName: outputName,
      mediaType: _mediaType(composition.output.container),
    );
  }

  List<String> _renderArguments(
    MediaComposition composition,
    List<MediaSource> sources,
  ) {
    final indices = <MediaSource, int>{
      for (var index = 0; index < sources.length; index++)
        sources[index]: index,
    };
    final filters = <String>[
      'color=c=0x${composition.backgroundColor}:s=${composition.width}x${composition.height}'
          ':r=${composition.framesPerSecond}:d=${_seconds(composition.duration)}[base]',
    ];
    var visualOutput = 'base';
    var visualNumber = 0;
    final audioLabels = <String>[];
    final visualCounts = <int, int>{};
    final audioCounts = <int, int>{};
    for (final layer in composition.layers) {
      final index = indices[layer.source]!;
      final counts = layer is MediaAudioLayer ? audioCounts : visualCounts;
      counts[index] = (counts[index] ?? 0) + 1;
    }
    for (final entry in visualCounts.entries.where(
      (entry) => entry.value > 1,
    )) {
      filters.add(
        '[${entry.key}:v]split=${entry.value}'
        '${List.generate(entry.value, (index) => '[input${entry.key}v$index]').join()}',
      );
    }
    for (final entry in audioCounts.entries.where((entry) => entry.value > 1)) {
      filters.add(
        '[${entry.key}:a]asplit=${entry.value}'
        '${List.generate(entry.value, (index) => '[input${entry.key}a$index]').join()}',
      );
    }
    final visualUses = <int, int>{};
    final audioUses = <int, int>{};
    for (final layer in composition.layers) {
      final input = indices[layer.source]!;
      if (layer is MediaAudioLayer) {
        final label = 'audio${audioLabels.length}';
        filters.add(
          '[${_streamLabel(input, 'a', audioCounts, audioUses)}]'
          'asetpts=PTS-STARTPTS,'
          'atrim=start=${_seconds(layer.sourceRange.start)}:'
          'duration=${_seconds(layer.sourceRange.duration)},'
          'asetpts=PTS-STARTPTS,'
          'adelay=delays=${_milliseconds(layer.timelineStart)}:all=1,'
          'volume=${layer.volume.toStringAsFixed(4)}[$label]',
        );
        audioLabels.add(label);
        continue;
      }
      final label = 'visual$visualNumber';
      filters.add(
        _visualFilter(
          _streamLabel(input, 'v', visualCounts, visualUses),
          label,
          layer,
          composition,
        ),
      );
      final next = 'composite$visualNumber';
      filters.add(
        _overlayFilter(visualOutput, label, next, layer, composition),
      );
      visualOutput = next;
      if (_transitionOf(layer)?.kind == MediaTransitionKind.dipToColor) {
        final dipped = 'dipped$visualNumber';
        filters.addAll(
          _dipFilters(
            visualOutput,
            'dipsource$visualNumber',
            'dip$visualNumber',
            dipped,
            layer,
            composition,
          ),
        );
        visualOutput = dipped;
      }
      visualNumber++;
    }
    const audioOutput = 'audioout';
    if (audioLabels.isEmpty) {
      filters.add(
        'anullsrc=r=48000:cl=stereo:d=${_seconds(composition.duration)}[$audioOutput]',
      );
    } else {
      filters.add(
        'anullsrc=r=48000:cl=stereo:d=${_seconds(composition.duration)}[silence]',
      );
      filters.add(
        '[silence]${audioLabels.map((label) => '[$label]').join()}'
        'amix=inputs=${audioLabels.length + 1}:duration=first:normalize=0,'
        'atrim=duration=${_seconds(composition.duration)},'
        'asetpts=PTS-STARTPTS[$audioOutput]',
      );
    }
    return [
      '-filter_complex',
      filters.join(';'),
      '-map',
      '[$visualOutput]',
      '-map',
      '[$audioOutput]',
      '-c:v',
      _videoEncoder(composition.output),
      '-b:v',
      composition.output.videoBitrate.toString(),
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      _audioEncoder(composition.output),
      '-b:a',
      composition.output.audioBitrate.toString(),
      '-ar',
      '48000',
      '-ac',
      '2',
      '-t',
      _seconds(composition.duration),
      if (composition.output.container != MediaContainer.webm) ...[
        '-movflags',
        '+faststart',
      ],
    ];
  }

  Future<Uint8List> _readSource(
    MediaSource source,
    MediaLimits mediaLimits,
    EditorRenderCancellationToken cancellation,
  ) async {
    final iterator = StreamIterator<List<int>>(source.openRead());
    final builder = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(mediaLimits.sourceReadTimeout);
    try {
      while (true) {
        cancellation.throwIfCancelled();
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw EditorValidationException(
            'Source ${source.id} did not finish before its read deadline.',
          );
        }
        final hasNext =
            await Future.any<bool>([
              iterator.moveNext(),
              cancellation.whenCancelled.then<bool>((_) {
                throw const EditorRenderCancelledException();
              }),
            ]).timeout(
              remaining,
              onTimeout: () => throw EditorValidationException(
                'Source ${source.id} did not finish before its read deadline.',
              ),
            );
        if (!hasNext) break;
        final chunk = iterator.current;
        if (chunk.any((byte) => byte < 0 || byte > 255) ||
            builder.length + chunk.length > source.byteLength) {
          throw EditorValidationException(
            'Source ${source.id} emitted invalid or excess bytes.',
          );
        }
        builder.add(chunk);
      }
    } finally {
      try {
        await iterator.cancel().timeout(mediaLimits.sourceCancellationTimeout);
      } on TimeoutException {
        // A caller-owned stream is allowed to be non-cooperative, but it must
        // not retain the editor operation beyond the explicit cleanup bound.
      }
    }
    if (builder.length != source.byteLength) {
      throw EditorValidationException(
        'Source ${source.id} emitted ${builder.length} bytes; '
        '${source.byteLength} were declared.',
      );
    }
    return builder.takeBytes();
  }

  Future<Uint8List> _rasterize(
    EditorCaptionRasterRequest request,
    EditorRenderCancellationToken cancellation,
  ) {
    final work = captionRasterizer.rasterize(
      request,
      cancellation: cancellation,
    );
    final cancelled = cancellation.whenCancelled.then<Uint8List>((_) {
      throw const EditorRenderCancelledException();
    });
    final timeout = Completer<Uint8List>();
    final timer = Timer(limits.captionRasterTimeout, () {
      timeout.completeError(
        EditorValidationException(
          'Caption ${request.clip.id} rasterization timed out.',
        ),
      );
      cancellation.cancel();
    });
    return Future.any<Uint8List>([
      work,
      cancelled,
      timeout.future,
    ]).whenComplete(timer.cancel);
  }
}

void _resolveTransitions(
  EditorProject project,
  Map<String, MediaVisualTransition> arrivals,
  Map<String, MediaTime> holds,
) {
  for (final lane in project.lanes) {
    if (lane.hidden || lane.kind != EditorLaneKind.video) continue;
    for (final clip in lane.clips.whereType<EditorVideoClip>()) {
      final transition = clip.transition;
      if (transition == null) continue;
      final previous = editorTransitionPredecessor(lane, clip);
      var span = transition.duration.microseconds;
      span = math.min(span, clip.duration.microseconds);
      if (previous != null) {
        span = math.min(span, previous.duration.microseconds);
      }
      if (span <= 0) continue;
      final duration = MediaTime.microseconds(span);
      arrivals[clip.id] = MediaVisualTransition(
        kind: _mediaTransitionKind(transition.kind),
        duration: duration,
        color: transition.color,
        overCut: previous != null,
      );
      if (previous != null && transition.needsOutgoingHold) {
        holds[previous.id] = duration;
      }
    }
  }
}

MediaTransitionKind _mediaTransitionKind(EditorTransitionKind kind) =>
    switch (kind) {
      EditorTransitionKind.dissolve => MediaTransitionKind.dissolve,
      EditorTransitionKind.dipToColor => MediaTransitionKind.dipToColor,
      EditorTransitionKind.slideFromLeft => MediaTransitionKind.slideFromLeft,
      EditorTransitionKind.slideFromRight => MediaTransitionKind.slideFromRight,
      EditorTransitionKind.slideFromTop => MediaTransitionKind.slideFromTop,
      EditorTransitionKind.slideFromBottom =>
        MediaTransitionKind.slideFromBottom,
    };
